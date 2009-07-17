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
use Vyatta::Interface;
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

sub set_mode {
    my ($intf, $mode) = @_;
    my $val = $modes{$mode};
    die "Unknown bonding mode $mode\n" unless $val;

    open my $fm, '>', "/sys/class/net/$intf/bonding/mode"
	or die "Error: $intf is not a bonding device:$!\n";
    print {$fm} $val, "\n";
    close $fm
	or die "Error: $intf can not set mode $val:$!\n";
}


sub change_mode {
    my ($intf, $mode) = @_;
    my $interface = new Vyatta::Interface($intf);

    die "$intf is not a valid interface" unless $interface;
    if ($interface->up()) {
	system "sudo ip link set $intf down"
	    and die "Could not set $intf down ($!)\n";

	set_mode($intf, $mode);

	system "sudo ip link set $intf up"
	    and die "Could not set $intf up ($!)\n";
    } else {
	set_mode($intf, $mode);
    }
}

sub usage {
    print "Usage: $0 --set-mode=s{2}\n";
    exit 1;
}

my @mode_change;

GetOptions(
    'set-mode=s{2}'     => \@mode_change,
) or usage();

change_mode( @mode_change )	if @mode_change;
