#!/usr/bin/perl

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

use strict;
use lib "/opt/vyatta/share/perl5";
use Vyatta::Config;

my $PAM_RAD_CFG   = '/etc/pam_radius_auth.conf';
my $PAM_RAD_BEGIN = '# BEGIN Vyatta Radius servers';
my $PAM_RAD_END   = '# END Vyatta Radius servers';

sub is_pam_radius_present {
    open( my $auth , '<' , '/etc/pam.d/common-auth' ) 
	or die "Cannot open /etc/pam.d/common-auth\n";

    my $present;
    while (<$auth>) {
        if (/\ssufficient\spam_radius_auth\.so$/) {
            $present = 1;
            last;
        }
    }
    close $auth;
    return $present;
}

sub remove_pam_radius {
    return 1 if ( !is_pam_radius_present() );
    my $cmd =
        'sudo sh -c "'
      . 'sed -i \'/\tsufficient\tpam_radius_auth\.so$/d;'
      . '/\tpam_unix\.so /{s/ use_first_pass$//}\' '
      . '/etc/pam.d/common-auth && '
      . 'sed -i \'/\tsufficient\tpam_radius_auth\.so$/d\' '
      . '/etc/pam.d/common-account"';
    system($cmd);
    return 0 if ( $? >> 8 );
    return 1;
}

sub add_pam_radius {
    return 1 if ( is_pam_radius_present() );
    my $cmd =
        'sudo sh -c "'
      . 'sed -i \'s/^\(auth\trequired\tpam_unix\.so.*\)$'
      . '/auth\tsufficient\tpam_radius_auth.so\n\1 use_first_pass/\' '
      . '/etc/pam.d/common-auth && '
      . 'sed -i \'s/^\(account\trequired\tpam_unix\.so.*\)$'
      . '/account\tsufficient\tpam_radius_auth.so\n\1/\' '
      . '/etc/pam.d/common-account"';
    system($cmd);
    return 0 if ( $? >> 8 );
    return 1;
}

sub remove_radius_servers {
    system( "sudo sed -i '/^$PAM_RAD_BEGIN\$/,/^$PAM_RAD_END\$/{d}' "
          . "$PAM_RAD_CFG" );
    return 0 if ( $? >> 8 );
    return 1;
}

sub add_radius_servers {
    my $str = shift;
    system( "sudo sh -c \""
          . "echo '$PAM_RAD_BEGIN\n$str$PAM_RAD_END\n' >> $PAM_RAD_CFG\"" );
    return 0 if ( $? >> 8 );
    return 1;
}

# handle "radius-server"
my $rconfig = new Vyatta::Config;
$rconfig->setLevel("system login radius-server");
my %servers     = $rconfig->listNodeStatus();
my @server_keys = sort keys %servers;
if ( scalar(@server_keys) <= 0 ) {

    # all radius servers deleted
    exit 1 if ( !remove_pam_radius() );
    exit 0;
}

# we have some servers
my $all_deleted = 1;
my $server_str  = '';
remove_radius_servers();

for my $server (@server_keys) {
    if ( $servers{$server} ne 'deleted' ) {
        $all_deleted = 0;
        my $port    = $rconfig->returnValue("$server port");
        my $secret  = $rconfig->returnValue("$server secret");
        my $timeout = $rconfig->returnValue("$server timeout");
        $server_str .= "$server:$port\t$secret\t$timeout\n";
    }
}

if ($all_deleted) {
    # all radius servers deleted
    exit 1 if ( !remove_pam_radius() );
} else {
    exit 1 if ( !add_radius_servers($server_str) );
    exit 1 if ( !add_pam_radius() );
}
