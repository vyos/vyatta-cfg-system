#!/usr/bin/perl
# Check to see if the supplied IPv4 or IPv6 address is an existing local address

use strict;
use lib "/opt/vyatta/share/perl5";
use Vyatta::Misc;

my $port = $ARGV[0];

if(!defined($port) || !is_port_available($port)) {
    exit 1;
} else {
    exit 0;
}