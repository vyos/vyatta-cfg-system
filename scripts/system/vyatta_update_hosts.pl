#!/usr/bin/perl -w
#
# Module: vyatta_update_hosts.pl
#
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
# Portions created by Vyatta are Copyright (C) 2012 Vyatta, Inc.
# All Rights Reserved.
#
# Description:
# Script to update '/etc/hosts' on commit of 'system host-name' and
# 'system domain-name' config.
#
# **** End License ****
#

use strict;
use lib "/opt/vyatta/share/perl5/";

use File::Temp qw(tempfile);
use Vyatta::File qw(touch);
use Vyatta::Config;

my $HOSTS_CFG  = '/etc/hosts';
my $HOSTS_TMPL  = "/tmp/hosts.XXXXXX";
my $HOSTNAME_CFG = '/etc/hostname';
my $MAILNAME_CFG = '/etc/mailname';

sub set_hostname {
    my ( $hostname ) = @_;
    system("hostname $hostname");
    open (my $f, '>', $HOSTNAME_CFG)
        or die("$0:  Error!  Unable to open $HOSTNAME_CFG for output: $!\n");
    print $f "$hostname\n";
    close ($f);
}

sub set_mailname {
    my ( $mailname ) = @_;
    open (my $f, '>', $MAILNAME_CFG)
        or die("$0:  Error!  Unable to open $MAILNAME_CFG for output: $!\n");
    print $f "$mailname\n";
    close ($f);
}

my $vc = new Vyatta::Config();

$vc->setLevel('system');
my $host_name = $vc->returnValue('host-name');
my $domain_name = $vc->returnValue('domain-name');
my $mail_name;
my $hosts_line = "127.0.1.1\t ";

if (! defined $host_name) {
    $host_name = 'vyatta';
}
$mail_name = $host_name;

if (defined $domain_name) {
    $mail_name .= '.' . $domain_name;
    $hosts_line .= $host_name . '.' . $domain_name;
}
$hosts_line .= " $host_name\t #vyatta entry\n";

set_hostname $host_name;
set_mailname $mail_name;

my ($out, $tempname) = tempfile($HOSTS_TMPL, UNLINK => 1)
  or die "Can't create temp file: $!";

if (! -e $HOSTS_CFG) {
    touch $HOSTS_CFG;
}
open (my $in, '<', $HOSTS_CFG)
    or die("$0:  Error!  Unable to open '$HOSTS_CFG' for input: $!\n");

while (my $line = <$in>) {
    if ($line =~ m:^127.0.1.1:) {
        next;
    }
    print $out $line;
}
print $out $hosts_line;

close ($in);
close ($out);

system("sudo cp $tempname $HOSTS_CFG") == 0
  or die "Can't copy $tempname to $HOSTS_CFG: $!";

