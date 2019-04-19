# **** License ****
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 2 as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# This code was originally developed by Vyatta, Inc.
# Portions created by Vyatta are Copyright (C) 2007 Vyatta, Inc.
# All Rights Reserved.
#
# **** End License ****

package Vyatta::Login::Radius;
use strict;
use warnings;
use lib "/opt/vyatta/share/perl5";
use Vyatta::Config;
use File::Compare;
use File::Copy;

my $PAM_RAD_CFG = '/etc/pam_radius_auth.conf';
my $PAM_RAD_TMP = "/tmp/pam_radius_auth.$$";

my $PAM_RAD_AUTH = "/usr/share/pam-configs/radius";
my $PAM_RAD_SYSCONF = "/opt/vyatta/etc/pam_radius.cfg";

sub remove_pam_radius {
    system('sed -i -e \'/^passwd:.*mapuid[ \t]/s/mapuid[ \t]//\' \
           -e \'/^passwd:.*[ \t]mapname/s/[ \t]mapname//\' \
           -e \'/^group:.*[ \t]mapname/s/[ \t]mapname//\' \
           -e \'s/[ \t]*$//\' \
           /etc/nsswitch.conf');

    system("DEBIAN_FRONTEND=noninteractive " .
	   "pam-auth-update --package --remove radius") == 0
	or die "pam-auth-update remove failed";

    unlink($PAM_RAD_AUTH)
	or die "Can't remove $PAM_RAD_AUTH";
}

sub add_pam_radius {
    copy($PAM_RAD_SYSCONF,$PAM_RAD_AUTH)
	or die "Can't copy $PAM_RAD_SYSCONF to $PAM_RAD_AUTH";

    system("DEBIAN_FRONTEND=noninteractive " .
	   "pam-auth-update --package radius") == 0
	or die "pam-auth-update add failed";

    system('sed -i -e \'/\smapname/b\' \
           -e \'/^passwd:/s/\s\s*/&mapuid /\' \
           -e \'/^passwd:.*#/s/#.*/mapname &/\' \
           -e \'/^passwd:[^#]*$/s/$/ mapname &/\' \
           -e \'/^group:.*#/s/#.*/ mapname &/\' \
           -e \'/^group:[^#]*$/s/: */&mapname /\' \
           /etc/nsswitch.conf') == 0
        or die "NSS configuration failed";
}

sub update {
    my $rconfig  = new Vyatta::Config;
    $rconfig->setLevel("system login radius");
    my %servers  = $rconfig->listNodeStatus("server");
    my $count    = 0;
    my $bindaddr = $rconfig->returnValue("source-address");
    if (!defined($bindaddr)) {
        $bindaddr = "0";
    }

    open (my $cfg, ">", $PAM_RAD_TMP)
	or die "Can't open config tmp: $PAM_RAD_TMP :$!";

    print $cfg "# RADIUS configuration file\n";
    print $cfg "# automatically generated do not edit\n";
    print $cfg "# server[:port]\t\tshared_secret\t\t\ttimeout (s)\tsource_ip\n";

    for my $server ( sort keys %servers ) {
	next if ( $servers{$server} eq 'deleted' );
	my $port    = $rconfig->returnValue("server $server port");
	my $secret  = $rconfig->returnValue("server $server key");
	my $timeout = $rconfig->returnValue("server $server timeout");
	print $cfg "$server:$port\t$secret\t$timeout\t$bindaddr\n";
	++$count;
    print $cfg "priv-lvl 15\n";
    print $cfg "mapped_priv_user radius_priv_user\n";
    }
    close($cfg);

    if ( compare( $PAM_RAD_CFG, $PAM_RAD_TMP ) != 0 ) {
	copy ($PAM_RAD_TMP, $PAM_RAD_CFG)
              or die "Copy of $PAM_RAD_TMP to $PAM_RAD_CFG failed";
    }
    unlink($PAM_RAD_TMP);

    if ( $count > 0 ) {
        add_pam_radius();
    } else {
        remove_pam_radius();
    }
}

1;
