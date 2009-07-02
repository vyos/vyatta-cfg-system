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
    ## Linux bonding driver modes + 1
    ## (eg. bond driver expects round-robin = 0)
    "invalid_opt"           => 0,
    "round-robin"           => 1,
    "active-backup"         => 2,
    "xor-hash"              => 3,
    "broadcast"             => 4,
    "802.3ad"               => 5,
    "transmit-load-balance" => 6,
    "adaptive-load-balance" => 7,
);

sub set_mode {
    my ($intf, $mode) = @_;
    my $request_mode = $mode;
    my $val = $modes{$mode};

    ## Check if vaild bonding option is requested.
    foreach my $item ( keys(%modes) ) {
	$mode = "invalid_opt" unless( $mode =~ m/$item/);
    };
    die "Unknown bonding mode $request_mode\n" unless $val;

    ## After above bonding option check, adjust value
    ##    to value the expected by bonding driver. -MOB
    $val = ($val - 1);

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
