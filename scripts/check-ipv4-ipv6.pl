#! /usr/bin/perl

# Trivial script to check for valid IPv4 or IPv6 address

use strict;
use NetAddr::IP; 

foreach my $addr (@ARGV) {
    die "$addr: not valid a valid IPv4 or IPv6 address\n"
	unless new NetAddr::IP $addr;
}

