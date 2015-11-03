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

sub set_mode {
    my ( $intf, $mode ) = @_;
    my $val = $modes{$mode};
    die "Unknown bonding mode $mode\n" unless defined($val);

    open my $fm, '>', "/sys/class/net/$intf/bonding/mode"
      or die "Error: $intf is not a bonding device:$!\n";
    print {$fm} $val, "\n";
    close $fm
      or die "Error: $intf can not set mode $val:$!\n";
}

sub set_hash_policy {
    my ( $intf, $hash ) = @_;

    open my $fm, '>', "/sys/class/net/$intf/bonding/xmit_hash_policy"
      or die "Error: $intf is not a bonding device:$!\n";
    print {$fm} $hash, "\n";
    close $fm
      or die "Error: $intf can not set hash $hash:$!\n";
}

sub get_slaves {
    my $intf = shift;

    open my $f, '<', "/sys/class/net/$intf/bonding/slaves"
      or die "$intf is not a bonding interface";
    my $slaves = <$f>;
    close $f;
    return unless $slaves;

    chomp $slaves;
    return split( ' ', $slaves );
}

sub add_slave {
    my ( $intf, $slave ) = @_;
    my $sysfs_slaves = "/sys/class/net/$intf/bonding/slaves";

    open my $f, '>', $sysfs_slaves
	or die "Can't open $sysfs_slaves: $!";

    print {$f} "+$slave\n";
    close $f;
}

sub remove_slave {
    my ( $intf, $slave ) = @_;
    my $sysfs_slaves = "/sys/class/net/$intf/bonding/slaves";

    open my $f, '>', $sysfs_slaves
	or die "Can't open $sysfs_slaves: $!";

    print {$f} "-$slave\n";
    close $f;
}

# Go dumpster diving to figure out which ethernet interface (if any)
# gave it's address to be used by all bonding devices.
sub primary_slave {
    my ( $intf, $bond_addr ) = @_;

    open my $p, '<', "/proc/net/bonding/$intf"
      or die "Can't open /proc/net/bonding/$intf : $!";

    my ( $dev, $match );
    while ( my $line = <$p> ) {
        chomp $line;
        if ( $line =~ m/^Slave Interface: (.*)$/ ) {
            $dev = $1;
        }
        elsif ( $line =~ m/^Permanent HW addr: (.*)$/ ) {
            if ( $1 eq $bond_addr ) {
                $match = $dev;
                last;
            }
        }
    }
    close $p;

    return $match;
}

sub get_irq_affinity {
    my $intf = shift;
    my $cfg = new Vyatta::Config;

    my $slaveif = new Vyatta::Interface($intf);
    unless ($slaveif) {
	warn "$intf: unknown interface type";
	return;
    }
    $cfg->setLevel($slaveif->path());
    return $cfg->returnValue('smp-affinity');
}

sub if_down {
    my $intf = shift;
    system "ip link set dev $intf down"
      and die "Could not set $intf up ($!)\n";
}

sub if_up {
    my $intf = shift;
    system "ip link set dev $intf up"
      and die "Could not set $intf up ($!)\n";

    my $smp_affinity = get_irq_affinity($intf);
    if ($smp_affinity) {
	system "/opt/vyatta/sbin/irq-affinity.pl $intf $smp_affinity"
	    and warn "Could not set $intf smp-affinity $smp_affinity\n";
    }
}

# Can't change mode when bond device is up and slaves are attached
sub change_mode {
    my ( $intf, $mode ) = @_;
    my $interface = new Vyatta::Interface($intf);
    die "$intf is not a valid interface" unless $interface;

    my $bond_up = $interface->up();

    if_down($intf) if ($bond_up);

    # Remove all interfaces; do primary last
    my $primary = primary_slave( $intf, $interface->hw_address());
    my @slaves = get_slaves($intf);

    foreach my $slave (@slaves) {
	remove_slave( $intf, $slave ) unless ( $primary && $slave eq $primary );
    }
    remove_slave( $intf, $primary ) if ($primary);

    set_mode( $intf, $mode );

    add_slave( $intf, $primary) if ($primary);
    foreach my $slave ( @slaves ) {
	add_slave( $intf, $slave ) unless ($primary && $slave eq $primary);
    }
    if_up($intf) if ($bond_up);
}

# Can't change hash when bond device is up
sub change_hash {
    my ( $intf, $hash ) = @_;
    my $interface = new Vyatta::Interface($intf);
    die "$intf is not a valid interface" unless $interface;
    my $bond_up = $interface->up();

    if_down($intf) if $bond_up;
    set_hash_policy( $intf, $hash );
    if_up($intf) if $bond_up;
}

# Consistency checks prior to commit
sub commit_check {
    my ( $intf, $slave ) = @_;
    my $cfg = new Vyatta::Config;

    die "Bonding interface $intf does not exist\n"
	unless ( -d "/sys/class/net/$intf" );

    my $slaveif = new Vyatta::Interface($slave);
    die "$slave: unknown interface type" unless $slaveif;
    $cfg->setLevel($slaveif->path());

    die "Error: can not add disabled interface $slave to bond-group $intf\n"
	if $cfg->exists('disable');

    die "Error: can not add interface $slave that is part of bridge to bond-group\n"
	if defined($cfg->returnValue("bridge-group bridge"));

    my @addr = $cfg->returnValues('address');
    die "Error: can not add interface $slave with addresses to bond-group\n"
	if (@addr);

    my @vrrp = $cfg->listNodes('vrrp vrrp-group');
    die "Error: can not add interface $slave with VRRP to bond-group\n"
	if (@vrrp);

    $cfg->setLevel('interfaces pseudo-ethernet');
    foreach my $peth ($cfg->listNodes()) {
	my $link = $cfg->returnValue("$peth link");

	die "Error: can not add interface $slave to bond-group already used by pseudo-ethernet $peth\n"
	    if ($link eq $slave);
    }
}

# bonding requires interface to be down before enslaving
# but enslaving automatically brings interface up!
sub add_port {
    my ( $intf, $slave ) = @_;
    my $cfg = new Vyatta::Config;
    my $slaveif = new Vyatta::Interface($slave);
    die "$slave: unknown interface type" unless $slaveif;

    $cfg->setLevel($slaveif->path());
    my $old = $cfg->returnOrigValue('bond-group');

    if_down($slave) if ($slaveif->up());
    remove_slave($old, $slave) if $old;
    add_slave ($intf, $slave);
}

sub remove_port {
   my ( $intf, $slave ) = @_;

   remove_slave ($intf, $slave);
   if_up ($slave);
}

sub usage {
    print "Usage: $0 --dev=bondX --mode={mode}\n";
    print "       $0 --dev=bondX --hash=layerX\n";
    print "       $0 --dev=bondX --add=ethX\n";
    print "       $0 --dev=bondX --remove=ethX\n";
    print print "modes := ", join( ',', sort( keys %modes ) ), "\n";

    exit 1;
}

my ( $dev, $mode, $hash, $add_port, $rem_port, $check );

GetOptions(
    'dev=s'    => \$dev,
    'mode=s'   => \$mode,
    'hash=s'   => \$hash,
    'add=s'    => \$add_port,
    'remove=s' => \$rem_port,
    'check=s'  => \$check,
) or usage();

die "$0: device not specified\n" unless $dev;

commit_check($dev, $check)             if $check;
change_mode( $dev, $mode )	if $mode;
change_hash( $dev, $hash )	if $hash;
add_port( $dev, $add_port )	if $add_port;
remove_port( $dev, $rem_port )  if $rem_port;
