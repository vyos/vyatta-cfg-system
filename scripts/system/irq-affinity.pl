#!/usr/bin/perl

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
# Portions created by Vyatta are Copyright (C) 2009,2010 Vyatta, Inc.
# All Rights Reserved.
#
# **** End License ****
#
use warnings;
use strict;
use Sys::Syslog qw(:standard :macros);

die "Usage: $0 ifname {auto | mask}\n" if ($#ARGV < 1);

my ($ifname, $mask)  = @ARGV;

die "Error: Interface $ifname does not exist\n"
    unless -d "/sys/class/net/$ifname";

openlog("irq-affinity","",LOG_LOCAL0);

my ( $cpus, $cores ) = cpuinfo();

if ($mask eq 'auto') {
    affinity_auto($ifname);
} else {
    affinity_mask($ifname, $mask);
}

exit 0;

# Get current irq assignments by reading /proc/interrupts
sub irqinfo {
    my $irqmap;

    open( my $f, '<', "/proc/interrupts" )
      or die "Can't read /proc/interrupts";

    while (<$f>) {
        chomp;
        my @cols = split;

        # First column is IRQ number (and colon)
        next unless /^\s*(\d+):\s/;
	my $irq = $1;

        # Skip columns for IRQ's per CPU
        foreach my $name ( @cols[ $cpus+1 .. $#cols ] ) {
            $name =~ s/,$//;
	    $irqmap->{$name} = $irq;
        }
    }
    close $f;

    return $irqmap;
}

# Determine number of cpus and cores
sub cpuinfo {
    my ( $cpu, $core );

    open( my $f, '<', "/proc/cpuinfo" )
      or die "Can't read /proc/cpuinfo";

    while (<$f>) {
        chomp;
        if (/^cpu cores\s+:\s(\d+)$/) {
            $core = $1;
        }
        elsif (/^processor\s+:\s+(\d)$/) {
            $cpu = $1;
        }
    }
    close $f;

    return ( $cpu + 1, $core );
}

# Determine hyperthreading factor
# most CPU's have either 1 or 2 threads per core
sub threads_per_core {
    return 1 unless defined($cores);

    return $cpus / $cores;
}

# Set affinity value for a irq
sub set_affinity {
    my ( $ifname, $irq, $mask ) = @_;
    my $smp_affinity = "/proc/irq/$irq/smp_affinity";

    syslog(LOG_INFO, "%s: irq %d affinity set to 0x%x", $ifname, $irq, $mask);

    open( my $f, '>', $smp_affinity )
      or die "Can't open: $smp_affinity : $!\n";
    printf {$f} "%x\n", $mask;
    close $f;
}

# set Receive Packet Steering mask
sub set_rps {
    my ( $ifname, $q, $mask ) = @_;

    # ignore if older kernel without RPS
    my $rxq = "/sys/class/net/$ifname/queues";
    return unless ( -d $rxq );

    syslog(LOG_INFO, "%s: receive queue %d cpus set to 0x%x",
	   $ifname, $q, $mask);

    my $rps_cpus = "$rxq/rx-$q/rps_cpus";
    open( my $f, '>', $rps_cpus )
	or die "Can't open: $rps_cpus : $!\n";
    printf {$f} "%x\n", $mask;
    close $f;
}

# For multi-queue NIC choose next cpu to be on next core
# FIXME assumes all cpu's online
sub next_cpu {
    my $cpu = shift;
    my $threads = threads_per_core();

    $cpu += $threads;
    if ( $cpu >= $cpus ) {
	# wraparound to next thread on core 0
	$cpu = ($cpu + 1) % $threads;
    }

    return $cpu;
}

# First cpu to assign for the queues
sub first_cpu {
    my ($ifname, $numq) = @_;

    # For multi-queue nic's always starts with 0
    #   This is less than ideal when there are more core's available
    #   than number of queues (probably should barber pole);
    #   but the Intel IXGBE needs CPU 0 <-> queue 0 because of flow director
    return 0 if ($numq > 1);

    # For single-queue nic choose IRQ based on name
    #   Ideally should make decision on least loaded CPU
    my ($ifunit) = ($ifname =~ m/^[a-z]*(\d+)$/);
    die "can't find number for $ifname\n"
	unless defined($ifunit);

    my $threads = threads_per_core();
    return ( $ifunit * $threads ) % $cpus;
}

# Assignment for multi-queue NICs
# Assign each queue to successive cores
sub assign_multiqueue {
    my ( $ifname, $numq, $irqmap, $irqfmt ) = @_;
    my $cpu = first_cpu($ifname, $numq);

    for ( my $q = 0 ; $q < $numq ; $q++ ) {
	# handles multiple irq's per interface (tx/rx)
        foreach my $fmt (@$irqfmt) {
            my $name = sprintf( $fmt, $ifname, $q );
            my $irq = $irqmap->{$name};

	    syslog(LOG_INFO, "%s: queue %d assign %s to cpu %d",
                $ifname, $q, $name, $cpu );

            # Assign CPU affinity for both IRQs
            set_affinity( $ifname, $irq, 1 << $cpu );

	    # TODO use RPS to steer data if cores > queues?
        }
        $cpu = next_cpu($cpu);
    }
}

# Affinity assignment function for single-queue NICs.  The strategy
# here is to just spread the interrupts of different NICs evenly
# across all CPUs.  That is the best we can do without monitoring the
# load and traffic patterns.  So we just directly map the NIC unit
# number into a CPU number.
sub assign_single {
    my ( $ifname, $irq ) = @_;
    my $cpu = first_cpu($ifname, 1);

    syslog( LOG_INFO, "%s: assign irq %d to cpu %d", $ifname, $irq, $cpu );

    set_affinity( $ifname, $irq, 1 << $cpu );

    my $threads = threads_per_core();
    if ($threads > 1) {
	# Use both threads on this cpu if hyperthreading
	my $mask = ((1 << $threads) - 1) << $cpu;
	set_rps($ifname, 0, $mask);
    }
    # MAYBE - Use all cpu's if no HT
}

# find irq number used for given interface using sysfs
sub get_irq {
    my $ifname = shift;

    # return (undefined) unless device has irq
    return unless open( my $irqf, '<', "/sys/class/net/$ifname/device/irq" );

    my $irq = <$irqf>;
    chomp $irq;
    close $irqf;

    return $irq;
}

# Mask must contain at least one CPU and
# no bits outside of range of available CPU's
sub check_mask {
    my ($ifname, $name, $mask) = @_;
    my $m = hex($mask);

    die "$ifname: $name mask $mask has no bits set\n"
	if ($m == 0);

    die "$ifname: $name mask $mask too large for number of CPU's: $cpus\n"
	if ($m >= 1 << $cpus);
}

# Set affinity (and RPS) based on mask
sub affinity_mask {
    my ($ifname, $mask) = @_;

    # match on <hex> or <hex>,<hex>
    unless ($mask =~ /^([0-9a-f]+)(|,([0-9a-f]+))$/) {
	die "$ifname: irq mask $mask is not a valid affinity mask\n"
    }

    my $irqmsk = $1;
    my $rpsmsk = $3;

    check_mask($ifname, "irq", $irqmsk);
    check_mask($ifname, "rps", $rpsmsk) if $rpsmsk;

    my $irq = get_irq($ifname);
    die "$ifname: attempt to assign affinity to device without irq\n"
	unless (defined($irq));

    set_affinity($ifname, $irq, hex($irqmsk));
    set_rps($ifname, 0, hex($rpsmsk)) if $rpsmsk;
}

# The auto strategy involves trying to achieve the following goals:
#
#  - Spread the receive load among as many CPUs as possible.
#
#  - For all multi-queue NICs in the system that provide both tx and
#    rx queues, keep all of the queues that share the same queue
#    number on same CPUs.  I.e. tx and rx queue 0 of all such NICs
#    should interrupt one CPU; tx and rx queue 1 should interrupt a
#    different CPU, etc.
#
#  - If hyperthreading is supported and enabled, avoid assigning
#    queues to both CPUs of a hyperthreaded pair if there are enough
#    CPUs available to do that.
sub affinity_auto {
    my $ifname   = shift;
    my $irqmap = irqinfo();
    my @irqnames = keys %{$irqmap};

    # Figure out what style of irq naming is being used
    my $numirq = grep { /$ifname/ } @irqnames;
    if ( $numirq <= 1 ) {
	my $irq = get_irq($ifname);
	assign_single( $ifname, $irq) if $irq;
    } else {
        my $nq = grep { /$ifname-rx-/ } @irqnames;

        if ( $nq > 0 ) {
            my $ntx = grep { /$ifname-tx-/ } @irqnames;
            die "$ifname: rx queues $nq != tx queues $ntx"
              unless ( $nq == $ntx );
	
            return assign_multiqueue( $ifname, $nq, $irqmap,
                [ '%s-rx-%d', '%s-tx-%d' ] );
        }

        $nq = grep { /$ifname-TxRx-/ } @irqnames;
        if ( $nq > 0 ) {
            return assign_multiqueue( $ifname, $nq, $irqmap, ['%s-TxRx-%d'] );
        }

        $nq = grep { /$ifname-\d$/ } @irqnames;
        if ( $nq > 0 ) {
            return assign_multiqueue( $ifname, $nq, $irqmap, ['%s-%d'] );
        }

        die "Unknown multiqueue device naming for $ifname\n";
    }
}
