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
use Getopt::Long;

my $dhclient_script = 0;

GetOptions("dhclient-script=i" => \$dhclient_script,
);

sub ntp_format {
    my ($cidr_or_host) = @_;
    my $ip = NetAddr::IP->new($cidr_or_host);
    if (defined($ip)) {
        my $address = $ip->addr();
        my $mask = $ip->mask();
    
        if ($ip->masklen() == 32) {
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
    } else {
        return undef;
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

my @servers;
my @clients;

if ($dhclient_script == 1) {
    @servers = $cfg->listOrigNodes("server");
    @clients = $cfg->returnOrigValues("client address");
} else {
    @servers = $cfg->listNodes("server");
    @clients = $cfg->returnValues("client address");
}

if (scalar(@servers) > 0) {
    print $output "# Servers\n\n";
    foreach my $server (@servers) {
        my $server_addr = ntp_format($server);
        if (defined($server_addr)) {
            print $output "server $server_addr iburst";
            for my $property (qw(dynamic noselect preempt prefer)) {
                if ($dhclient_script == 1) {
                    print $output " $property" if ($cfg->existsOrig("server $server $property"));
                } else {
                    print $output " $property" if ($cfg->exists("server $server $property"));
                }
            }
            print $output "\nrestrict $server_addr nomodify notrap nopeer noquery\n";
        }
    }
    print $output "\n";
}

if (scalar(@clients) > 0) {
    print $output "# Clients\n\n";
    foreach my $client (@clients) {
        my $address = ntp_format($client);
        print $output "restrict $address nomodify notrap nopeer\n";
    }
    print $output "\n";
}

exit 0;
