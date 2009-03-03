#!/usr/bin/perl
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
# A copy of the GNU General Public License is available as
# `/usr/share/common-licenses/GPL' in the Debian GNU/Linux distribution
# or on the World Wide Web at `http://www.gnu.org/copyleft/gpl.html'.
# You can also obtain it by writing to the Free Software Foundation,
# Free Software Foundation, Inc., 51 Franklin St, Fifth Floor, Boston,
# MA 02110-1301, USA.
#
# This code was originally developed by Vyatta, Inc.
# Portions created by Vyatta are Copyright (C) 2007 Vyatta, Inc.
# All Rights Reserved.
#
# Author: Stephen Hemminger
# Date: September 2008
# Description: Script to setup bonding interfaces
#
# **** End License ****
#

use lib "/opt/vyatta/share/perl5/";
use Vyatta::Config;

use Getopt::Long;
use strict;
use warnings;

my %modes = (
    "round-robin"           => 0,
    "active-backup"         => 1,
    "xor-hash"              => 2,
    "broadcast"             => 3,
    "802.3ad"               => 4,
    "transmit-load-balance" => 5,
    "adaptive-load-balance" => 6,
);

sub create_bond {
    my $bond   = shift;
    my $config = new Vyatta::Config;

    $config->setLevel("interfaces bonding $bond");
    my $mode = $modes{ $config->returnValue("mode") };
    defined $mode or die "bonding mode not defined";

    system("sudo modprobe -o \"$bond\" bonding mode=$mode") == 0
      or die "modprobe of bonding failed: $!\n";

    system("sudo ip link set \"$bond\" up") == 0
      or die "enabling $bond failed: $!\n";
}

sub delete_bond {
    my $bond = shift;
    system("sudo rmmod \"$bond\"") == 0
      or die "removal of bonding module failed: $!\n";
}

# See if bonding device exists and the mode has changed
sub change_bond {
    my $bond   = shift;
    my $config = new Vyatta::Config;

    $config->setLevel("interfaces bonding");
    if ( !( $config->isAdded($bond) || $config->isDeleted($bond) )
        && $config->isChanged("$bond mode") )
    {
        delete_bond($bond);
        create_bond($bond);
    }
    exit 0;
}

sub usage {
    print "Usage: $0 --create bondX\n";
    print "          --delete bondX\n";
    print "          --mode-change bondX\n";
    exit 1;
}

GetOptions(
    'create=s'      => sub { create_bond( $_[1] ); },
    'delete=s'      => sub { delete_bond( $_[1] ); },
    'mode-change=s' => sub { change_bond( $_[1] ); },
) or usage();

