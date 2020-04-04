#! /usr/bin/perl
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
# Date: November 2010
# Description: Script to setup bridge ports
#
# **** End License ****
#

use strict;
use warnings;

use lib "/opt/vyatta/share/perl5/";
use Vyatta::Interface;
use Vyatta::Config;

my $BRCTL = 'sudo /sbin/brctl';

die "Usage: $0 ACTION ethX\n" unless ($#ARGV == 1);

my ($action, $ifname) = @ARGV;

# Get bridge information from configuration
my $intf = new Vyatta::Interface($ifname);
die "Unknown interface type $ifname\n"
    unless $intf;

my $cfg = new Vyatta::Config;
# Change path for QinQ S-VLAN
my $vif_s_path = "interfaces $intf->{type} $intf->{dev} vif-s $intf->{vif}";
if (!$intf->{vif_c} && ($cfg->exists($vif_s_path) or $cfg->existsOrig($vif_s_path))) {
    $cfg->setLevel($vif_s_path);
}else {
    $cfg->setLevel($intf->path());
}

my $oldbridge = $cfg->returnOrigValue('bridge-group bridge');
my $newbridge = $cfg->returnValue('bridge-group bridge');
my $cost = $cfg->returnValue('bridge-group cost');
my $priority = $cfg->returnValue('bridge-group priority');

if (!defined($newbridge) && ($action ne 'SET')) {
    $action = 'DELETE';
}

if (!defined($oldbridge) && ($action ne 'DELETE')) {
    $action = 'SET';
}

if ($action eq 'SET') {
    die "Error: $ifname: not in a bridge-group\n"  unless $newbridge;

    die "Error: can not add interface $ifname that is part of bond-group to bridge\n"
        if defined($cfg->returnValue('bond-group'));

    my @address = $cfg->returnValues('address');
    die "Error: Can not add interface $ifname with addresses to bridge\n"
        if (@address);

    my @vrrp = $cfg->listNodes('vrrp vrrp-group');
    die "Error: Can not add interface $ifname with VRRP to bridge\n"
        if (@vrrp);

    $cfg->setLevel('interfaces pseudo-ethernet');
    foreach my $peth ($cfg->listNodes()) {
        my $link = $cfg->returnValue("$peth link");

        die "Error: can not add interface $ifname to bridge already used by pseudo-ethernet $peth\n"
            if ($link eq $ifname);
    }

    print "Adding interface $ifname to bridge $newbridge\n";
    add_bridge_port($newbridge, $ifname, $cost, $priority);

} elsif ($action eq 'DELETE') {
    die "Error: $ifname: not in a bridge-group\n"  unless $oldbridge;

    print "Removing interface $ifname from bridge $oldbridge\n";
    remove_bridge_port($oldbridge, $ifname);

} elsif ($oldbridge ne $newbridge) {
    print "Moving interface $ifname from $oldbridge to $newbridge\n";
    remove_bridge_port($oldbridge, $ifname);
    add_bridge_port($newbridge, $ifname, $cost, $priority);
}

exit 0;

sub add_bridge_port {
    my ($bridge, $port, $cost, $priority) = @_;
    system("$BRCTL addif $bridge $port") == 0
        or exit 1;

    if ($cost) {
        system("$BRCTL setpathcost $bridge $port $cost") == 0
            or exit 1;
    }

    if ($priority) {
        system("$BRCTL setportprio $bridge $port $priority") == 0
            or exit 1;
    }
}

sub remove_bridge_port {
    my ($bridge, $port) = @_;
    return unless $bridge;	# not part of a bridge

    # this is the case where the bridge that this interface is assigned
    # to is getting deleted in the same commit as the bridge node under
    # this interface - Bug 5064|4734. Since bridge has a higher priority;
    # it gets deleted before the removal of bridge-groups under interfaces
    return unless (-d "/sys/class/net/$bridge");

    system("$BRCTL delif $bridge $ifname") == 0
        or exit 1;
}
