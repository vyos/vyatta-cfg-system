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
use warnings;

use lib "/opt/vyatta/share/perl5";
use Vyatta::Config;

## setup tacacs+ server info
# add tacacs to PAM file
sub add_tacacs {
    my $param_string = shift;
    my $pam          = shift;

    my $cmd =
        'sudo sh -c "'
      . 'sed -i \'s/^\(' . "$pam"
      . '\trequired\tpam_unix\.so.*\)$/' . "$pam"
      . '\tsufficient\tpam_tacplus.so\t'
      . "$param_string # Vyatta"
      . '\n\1/\' '
      . "/etc/pam.d/common-$pam\"";

    system($cmd);
    return 0 if ( $? >> 8 );
    return 1;
}

# remove tacacs from PAM files
sub remove_tacacs {
    my $cmd =
        'sudo sh -c "'
      . 'sed -i \'/\(.*pam_tacplus.*# Vyatta\)/ D\' '
      . '/etc/pam.d/common-auth '
      . '/etc/pam.d/common-account '
      . '/etc/pam.d/common-session "';

    system($cmd);
    return 0 if ( $? >> 8 );
    return 1;
}

# main tacacs
# There is a race condition in here betwen radius and tacacs currently.
# Also should probably add a chack to see if we ned to actually reconfig
# PAM rather than jusy doing it each commit.
# Finally, service and protocol will need to be removed.  They are just
# in there for troubleshootig purposes right now.
#
my $tconfig = new Vyatta::Config;
if ( $tconfig->isDeleted("system login tacacs-plus") ) { remove_tacacs; }
$tconfig->setLevel("system login tacacs-plus");
my @tacacs_params = $tconfig->listNodes();

if ( scalar(@tacacs_params) > 0 ) {
    remove_tacacs;
    my ( $acctall, $debug, $firsthit, $noencrypt );
    if ( $tconfig->exists("acct-all") )   { $acctall   = 1; }
    if ( $tconfig->exists("debug") )      { $debug     = 1; }
    if ( $tconfig->exists("first-hit") )  { $firsthit  = 1; }
    if ( $tconfig->exists("no-encrypt") ) { $noencrypt = 1; }
    my $protocol = $tconfig->returnValue("protocol");
    my $secret   = $tconfig->returnValue("secret");
    my $server   = $tconfig->returnValue("server");
    my $service  = $tconfig->returnValue("service");

    if ( $server ne '' && $secret ne '' ) {
        my ( $authstr, $accountstr, $sessionstr, $ip );
        my @servers = split /\s/, $server;

        ## 3 common options
        # encrypt this session
        if ( !$noencrypt ) { $authstr = "encrypt "; }

        # single secret
        $authstr .= "secret=$secret ";

        # and debug
        if ($debug) { $authstr .= "debug "; }

        ## now they get specific
        $accountstr = $sessionstr = $authstr;

        # can be multiple servers for auth and session
        foreach my $ip (@servers) {
            $authstr    .= "server=$ip ";
            $sessionstr .= "server=$ip ";
        }

        # first hit for auth
        if ($firsthit) { $authstr .= "firsthit "; }

        # acctall for session
        if ($acctall) { $sessionstr .= "acctall "; }

        # service and protocol for account and session
        if ($service) {
            $accountstr .= "service=$service ";
            $sessionstr .= "service=$service ";
        }
        if ($protocol) {
            $accountstr .= "protocol=$protocol ";
            $sessionstr .= "protocol=$protocol ";
        }

        add_tacacs( "$authstr",    "auth" );
        add_tacacs( "$accountstr", "account" );
        add_tacacs( "$sessionstr", "session" );
    }
    else { exit 1; }
}

exit 0;
