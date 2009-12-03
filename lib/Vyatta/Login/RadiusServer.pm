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

package Vyatta::Login::RadiusServer;
use strict;
use warnings;
use lib "/opt/vyatta/share/perl5";
use Vyatta::Config;
use File::Compare;

my $PAM_RAD_CFG = '/etc/pam_radius_auth.conf';
my $PAM_RAD_TMP = "/tmp/pam_radius_auth.$$";

sub remove_pam_radius {
    return system("sudo DEBIAN_FRONTEND=noninteractive"
		  . " pam-auth-update --remove radius") == 0;
}

sub add_pam_radius {
    return system("sudo DEBIAN_FRONTEND=noninteractive"
		  . " pam-auth-update radius") == 0;
}

sub update {
    my $rconfig = new Vyatta::Config;
    $rconfig->setLevel("system login radius-server");
    my %servers = $rconfig->listNodeStatus();
    my $count   = 0;

    open (my $cfg, ">", $PAM_RAD_TMP)
	or die "Can't open config tmp: $PAM_RAD_TMP :$!";

    print $cfg "# RADIUS configuration file\n";
    print $cfg "# automatically generated do not edit\n";
    print $cfg "# Server\tSecret\tTimeout\n";

    for my $server ( sort keys %servers ) {
	next if ( $servers{$server} eq 'deleted' );
	my $port    = $rconfig->returnValue("$server port");
	my $secret  = $rconfig->returnValue("$server secret");
	my $timeout = $rconfig->returnValue("$server timeout");
	print $cfg "$server:$port\t$secret\t$timeout\n";
	++$count;
    }
    close($cfg);

    if ( compare( $PAM_RAD_CFG, $PAM_RAD_TMP ) != 0 ) {
	system("sudo cp $PAM_RAD_TMP $PAM_RAD_CFG") == 0
              or die "Copy of $PAM_RAD_TMP to $PAM_RAD_CFG failed";
    }
    unlink($PAM_RAD_TMP);

    if ( $count > 0 ) {
        exit 1 unless add_pam_radius();
    }
    else {
        exit 1 unless remove_pam_radius();
    }
}

1;
