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

die "$0 expects no arguments\n" if (@ARGV);

# Weed existing servers from config
print grep {! /^server/ } <STDIN>;

my $cfg = new Vyatta::Config;
$cfg->setLevel("service ntp");

foreach my $server ($cfg->listNodes("server")) {
    print "server $server iburst";
    for my $property qw(dynamic noselect preempt prefer) {
	print " $property" if ($cfg->exists("$server $property"));
    }
    print "\n";
}

exit 0;





    
