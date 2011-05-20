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

my $PATH_SYS_SYSTEM = "/sys/devices/system";
my $PATH_SYS_CPU0   = $PATH_SYS_SYSTEM . "/cpu/cpu0";

die "Usage: $0 ifname {auto | mask} { debug }\n" if ($#ARGV < 1);

my ($ifname, $mask, $debug)  = @ARGV;

die "Error: Interface $ifname does not exist\n"
    unless -d "/sys/class/net/$ifname";

my $logopt = defined($debug) ? "perror" : "";
openlog("irq-affinity", $logopt, LOG_LOCAL0);

my ($cpus, undef, $threads) = cpuinfo();

if ($mask eq 'auto') {
    affinity_auto($ifname);
} else {
    affinity_mask($ifname, $mask);
}

exit 0;

# Get current irq assignments by reading /proc/interrupts
# returns reference to hash of interrupt infromation for given interface
# i.e.  {'eth1'} => 22, {'eth1-tx-1'} => 31, ...
#
# Code based on parsing in irqbalance program
#
# Format of /proc/interrupts is:
#
#            CPU0       CPU1       
#  72:       1637          0   PCI-MSI-edge      eth3
sub irqinfo {
    my $ifname = shift;
    my $irqmap;

    open( my $f, '<', "/proc/interrupts" )
      or die "Can't read /proc/interrupts";

    # first line is the header we don't need
    <$f>;

    while (<$f>) {
        chomp;

	# lines with letters in front are special, like NMI count. 
	#
        # First column is IRQ number (and colon)
	# after that match as many entries with digits
        last unless /^\s*(\d+):\s/;
	my $irq = $1;

	my @cols = split;

	# skip the irq number and all counts
	do {
	    shift @cols;
	} while ($cols[0] =~ /^\d+$/);

	foreach my $name ( @cols ) {
            $name =~ s/,$//;

	    next unless ($name eq $ifname || $name =~ /^$ifname-/ );

	    $irqmap->{$name} = $irq;
        }
    }
    close $f;

    return $irqmap;
}


# count the bits set in a mapping file
sub path_sibling {
    my $path = shift;
    my $result = 0;

    open (my $f, '<', $path)
	or die "can't open $path : $!";

    my $line = <$f>;
    close $f;
    chomp $line;

    for my $mask (split(/,/, $line)) {
	my $bits = hex($mask);

	for (; $bits > 0; $bits /= 2) {
	    ++$result if ($bits & 1);
	}
    }

    return $result;
}

# Determine number of cpu topology information
#
# This algorithm is based on the command lscpu from util-linux
# it cases like multiple socket, offline cpus, etc
sub cpuinfo {
    my $cpu = 0;

    while ( -e $PATH_SYS_SYSTEM . '/cpu/cpu' . $cpu ) {
	++$cpu;
    }

    my $thread = path_sibling($PATH_SYS_CPU0 . '/topology/thread_siblings');
    my $core   = path_sibling($PATH_SYS_CPU0 . '/topology/core_siblings') / $thread;
    my $socket = $cpu / $core / $thread;
    
    syslog(LOG_DEBUG, "cpus=%d cores=%d threads=%d sockets=%d\n", 
	   $cpu, $core, $thread, $socket);

    return ($cpu, $core, $thread);
}

# Set affinity value for a irq
sub set_affinity {
    my ( $ifname, $irq, $mask ) = @_;
    my $smp_affinity = "/proc/irq/$irq/smp_affinity";

    syslog(LOG_DEBUG, "%s: irq %d affinity set to 0x%x", $ifname, $irq, $mask);

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

# Check if the current if this cpu is in the banned mask
# Uses environment variable VYATTA_IRQAFFINITY_BANNED_CPUS
#  to mask cpus which irq affinity script should ignore
sub skip_cpu {
    my $cpu = shift;
    my $banned = $ENV{'VYATTA_IRQAFFINITY_BANNED_CPUS'};

    return unless defined($banned);	# false

    return ((1 << $cpu) & hex($banned)) != 0;
}

# For multi-queue NIC choose next cpu to be on next core
sub next_cpu {
    my $origcpu = shift;
    my $cpu = $origcpu;

    do {
	$cpu += $threads;
	if ( $cpu >= $cpus ) {
	    # wraparound to next thread on core 0
	    $cpu = ($cpu + 1) % $threads;
	}
    } while ($cpu != $origcpu && skip_cpu($cpu));

    return $cpu;
}

# Get cpu to assign for the queues for single queue nic
sub choose_cpu {
    my $ifname = shift;

    # For single-queue nic choose IRQ based on name
    #   Ideally should make decision on least loaded CPU
    my ($ifunit) = ($ifname =~ m/^[a-z]*(\d+)$/);
    die "can't find number for $ifname\n"
	unless defined($ifunit);

    my $threads = threads_per_core();

    # Give the load first to one CPU of each hyperthreaded core, then
    # if there are enough NICs, give the load to the other CPU of
    # each core.
    my $ht_wrap = (($ifunit * $threads) / $cpus) % $threads;
    my $cpu = ((($ifunit * $threads) + $ht_wrap) % $cpus);

    $cpu = next_cpu($cpu) if skip_cpu($cpu);
    return $cpu;
}

# Assignment for multi-queue NICs
sub assign_multiqueue {
    my $ifname = shift;
    my $irqmap = shift;
    my $numq = scalar(@_);
    my $cpu;

    if ($numq == 1) {
	# This is a single-queue NIC using the multi-queue naming
	# format.  In this case, we use the same algorithm to select
	# the CPU as we use for standard single-queue NICs.  This
	# algorithm spreads the work of different NICs accross
	# different CPUs.

	$cpu = choose_cpu($ifname);
    } else {
	# For multi-queue nic's always starts with CPU 0
	#   This is less than ideal when there are more core's available
	#   than number of queues (probably should barber pole);
	#   but the Intel IXGBE needs CPU 0 <-> queue 0 
	#   because of flow director bug.

	$cpu = 0;
    }

    foreach my $name (sort @_) {
	my $irq = $irqmap->{$name};

	die "Can't find irq in map for $name\n" unless $irq;

	syslog(LOG_INFO, "%s: assign %s to cpu %d",
	       $ifname, $name, $cpu );

	# Assign CPU affinity for both IRQs
	set_affinity( $ifname, $irq, 1 << $cpu );

	# TODO use RPS to steer data if cores > queues?
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
    my $cpu = choose_cpu($ifname);

    syslog(LOG_INFO,"%s: assign irq %d to cpu %d", $ifname, $irq, $cpu );

    set_affinity( $ifname, $irq, 1 << $cpu );

    my $threads = threads_per_core();
    if ($threads > 1) {
	# Use both threads on this cpu if hyperthreading
	my $mask = ((1 << $threads) - 1) << $cpu;
	set_rps($ifname, 0, $mask);
    }
    # MAYBE - Use all cpu's if no HT
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

    my $irqmap = irqinfo($ifname);
    while (my ($name, $irq) = each (%{$irqmap})) {
	syslog(LOG_INFO, "%s: assign irq %d mask %s", $name, $irq, $irqmsk);
	set_affinity($name, $irq, hex($irqmsk));
    }

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

    my $irqmap = irqinfo($ifname);
    my @irqnames = keys %{$irqmap};
    my $numirq = scalar(@irqnames);

    # Figure out what style of irq naming is being used
    if ( $numirq == 1 ) {
	my $irq = $irqmap->{$ifname};
	assign_single( $ifname, $irq) if $irq;
    } elsif ($numirq > 1) {
	# Special case for paired Rx and Tx
	my @mirq = grep { /^$ifname-rx-/ } @irqnames;
	my $num_mirq = scalar(@mirq);
        if ( $num_mirq > 0 ) {
	    assign_multiqueue( $ifname, $irqmap, @mirq );

	    @mirq = grep { /^$ifname-tx-/ } @irqnames;
	    assign_multiqueue( $ifname, $irqmap, @mirq );
	    return;
	}

	# Normal case for single irq per queue
	@mirq = grep { /^$ifname-/ } @irqnames;
	$num_mirq = scalar(@mirq);
	if ( $num_mirq > 0 ) {
	    assign_multiqueue( $ifname, $irqmap, @mirq );
	    return;
	}

	# Netxen thought up yet another convention
	@mirq = grep { /^$ifname\[/ } @irqnames;
	if ( $#mirq > 0 ) {
	    assign_multiqueue( $ifname, $irqmap, @mirq );
	    return;
	}

	syslog(LOG_ERR, "%s: Unknown multiqueue irq naming: %s\n", $ifname,
	       join(' ', @irqnames));
    }
}
