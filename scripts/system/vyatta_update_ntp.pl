#! /usr/bin/perl

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

# Filter ntp.conf - remove old servers and add current ones

use strict;
use lib "/opt/vyatta/share/perl5";
use Vyatta::Config;
use NetAddr::IP;

die "$0 expects no arguments\n" if (@ARGV);

sub ntp_format {
    my ($cidr) = @_;
    my $ip = NetAddr::IP->new($cidr);
    die "$cidr: not a valid IP address" unless $ip;

    my $address = $ip->addr();
    my $mask = $ip->mask();
    
    if ($mask eq '255.255.255.255') {
        if ($ip->version() == 6) {
            return "-6 $address";
        } else {
            return "$address";
        }
    } else {
        if ($ip->version() == 6) {
            return "-6 $address mask $mask";
        } else {
            return "$address mask $mask";
        }
    }
}

my @ntp;
if (-e '/etc/ntp.conf') {
    open (my $file, '<', '/etc/ntp.conf')
        or die("$0:  Error!  Unable to open '/etc/ntp.conf' for input: $!\n");
    @ntp = <$file>;
    close ($file);
}

open (my $output, '>', '/etc/ntp.conf')
    or die("$0:  Error!  Unable to open '/etc/ntp.conf' for output: $!\n");

my $cfg = new Vyatta::Config;
$cfg->setLevel("system ntp");

foreach my $line (@ntp) {
   if ($line =~ /^# VyOS CLI configuration options/) {
       print $output $line;
       print $output "\n";
       last;
   } else {
       print $output $line;
   }
}

if ($cfg->exists("server")) {
    print $output "# Servers\n\n";
    foreach my $server ($cfg->listNodes("server")) {
        my $server_addr = ntp_format($server);
        print $output "server $server_addr iburst";
        for my $property (qw(dynamic noselect preempt prefer)) {
	    print $output " $property" if ($cfg->exists("server $server $property"));
        }
        print $output "\nrestrict $server_addr nomodify notrap nopeer noquery\n";
    }
    print $output "\n";
}

if ($cfg->exists("client")) {
    print $output "# Clients\n\n";
    my @clients = $cfg->returnValues("client address");
    foreach my $client (@clients) {
        my $address = ntp_format($client);
        print $output "restrict $address nomodify notrap nopeer\n";
    }
    print $output "\n";
}

exit 0;
