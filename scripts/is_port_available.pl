#!/usr/bin/perl
# Check to see if the supplied IPv4 or IPv6 address is an existing local address

use strict;
use lib "/opt/vyatta/share/perl5";
use Vyatta::Misc;

my $ip = $ARGV[0];
my $port = $ARGV[1];

if(!defined($ip) || !defined($port) || !is_port_available($ip, $port)) {
    exit 1;
} else {
    exit 0;
}