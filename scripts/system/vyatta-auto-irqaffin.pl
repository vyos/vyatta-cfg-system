#!/usr/bin/perl
#
# Module: vyatta-auto-irqaffin.pl
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
# This code was originally developed by Vyatta, Inc.
# Portions created by Vyatta are Copyright (C) 2009,2010 Vyatta, Inc.
# All Rights Reserved.
#
# Author: Bob Gilligan (gilligan@vyatta.com)
# Date: October 2009
# Description: Script to configure optimal IRQ affinity for NICs.
#
# **** End License ****
#

# This script attempts to set up a static CPU affinity for the IRQs
# used by network interfaces.  It is primarily targeted at supporting
# multi-queue NICs, but does include code to handle single-queue NICs.
# Since different NICs may have different queue organizations, and
# because there is no standard API for learning the mapping between
# queues and IRQ numbers, different code is required for each of the
# queue naming conventions.
#
# The general strategy involves trying to achieve the following goals:
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
#
# This strategy yields the greatest MP scaling possible for
# multi-queue NICs.  It also ensures that an individual skb is
# processed on the same CPU for the entirity of its lifecycle,
# including transmit time, which optimally utilizes the cache and
# keeps performance high.
#


use lib "/opt/vyatta/share/perl5";
use Getopt::Long;

use warnings;
use strict;

# Send output of shell commands to syslog for debugging and so that
# the user is not confused by it.  Log at debug level, which is supressed
# by default, so that we don't unnecessarily fill up the syslog file.
my $logger = 'logger -t firewall-cfg -p local0.debug --';

# Enable printing debug output to stdout.
my $debug_flag = 0;
my $syslog_flag = 0;

my $setup_ifname;

GetOptions("setup=s"		=> \$setup_ifname,
	   "debug"		=> \$debug_flag
    );

sub log_msg {
    my $message = shift;

    print "DEBUG: $message" if $debug_flag;
    system("$logger DEBUG: \"$message\"") if $syslog_flag;
}


# Affinity assignment function for the Intel igb, ixgb and ixgbe
# drivers, and any other NICs that follow their queue naming
# convention.  These NICs have an equal number of rx and tx queues.
# The first part of the strategy for optimal performance is to select
# the CPU to assign the IRQs to by mapping from the queue number.
# This ensures that all queues with the same queue number are assigned
# to the same CPU.  The second part is to avoid assigning any queues
# to the second CPU in a hyper-threaded pair, if posible.  I.e., if
# CPU 0 and 1 are hyper-threaded pairs, then assign a queue to CPU 0,
# but try to avoid assigning one to to CPU 1.  But if we have more
# queues than CPUs, then it is OK to assign some to the second CPU in
# a hyperthreaded pair.
# 
sub intel_func{
    my ($ifname, $numcpus, $numcores) = @_;
    my $rx_queues;	# number of rx queues
    my $tx_queues;	# number of tx queues
    my $ht_factor;	# 2 if HT enabled, 1 if not

    log_msg("intel_func was called.\n");

    if ($numcpus > $numcores) {
	$ht_factor = 2;
    } else {
	$ht_factor = 1;
    }

    log_msg("ht_factor is $ht_factor.\n");

    # Figure out how many queues we have

    $rx_queues=`grep "$ifname-rx-" /proc/interrupts | wc -l`;
    $rx_queues =~ s/\n//;

    $tx_queues=`grep "$ifname-tx-" /proc/interrupts | wc -l`;
    $tx_queues =~ s/\n//;

    log_msg("rx_queues is $rx_queues.  tx_queues is $tx_queues\n");
    
    if ($rx_queues != $tx_queues) {
	printf("Error: rx and tx queues don't match for igb driver.\n");
	exit 1;
    }

    # For i = 0 to number of queues:
    #    Affinity of rx and tx queue $i gets CPU ($i * (2 if HT, 1 if no HT)) 
    #                                   % number_of_cpus
    for (my $queue = 0, my $cpu = 0; ($queue < $rx_queues) ; $queue++) {
	# Generate the hex string for the bitmask representing this CPU
	my $cpu_bit = 1 << $cpu;
	my $cpu_hex = sprintf("%x", $cpu_bit);
	log_msg ("queue=$queue cpu=$cpu cpu_bit=$cpu_bit cpu_hex=$cpu_hex\n");
	
	# Get the IRQ number for RX queue
	my $rx_irq=`grep "$ifname-rx-$queue\$" /proc/interrupts | awk -F: '{print \$1}'`;
	$rx_irq =~ s/\n//;
	$rx_irq =~ s/ //g;

	# Get the IRQ number for TX queue
	my $tx_irq=`grep "$ifname-tx-$queue\$" /proc/interrupts | awk -F: '{print \$1}'`;
	$tx_irq =~ s/\n//;
	$tx_irq =~ s/ //g;

	log_msg("rx_irq = $rx_irq.  tx_irq = $tx_irq\n");

	# Assign CPU affinity for both IRQs
	system "echo $cpu_hex > /proc/irq/$rx_irq/smp_affinity";
	system "echo $cpu_hex > /proc/irq/$tx_irq/smp_affinity";

	$cpu += $ht_factor;

	if ($cpu >= $numcpus) {
	    # Must "wrap"
	    $cpu %= $numcpus;

	    if ($ht_factor > 1) {
		# Next time through, select the other CPU in a hyperthreaded 
		# pair.
		if ($cpu == 0) {
		    $cpu++;
		} else {
		    $cpu--;
		}
	    }
	}
    }
};


# Affinity setting function for NICs using new intel queue scheme
# that provides one IRQ for each pair of TX and RX queues
sub intel_new_func{
    my ($ifname, $numcpus, $numcores) = @_;
    my $txrx_queues;	# number of rx/rx queue pairs
    my $ht_factor;	# 2 if HT enabled, 1 if not

    log_msg("intel_new_func was called.\n");

    if ($numcpus > $numcores) {
	$ht_factor = 2;
    } else {
	$ht_factor = 1;
    }

    log_msg("ht_factor is $ht_factor.\n");

    # Figure out how many queues we have

    $txrx_queues=`grep "$ifname-TxRx-" /proc/interrupts | wc -l`;
    $txrx_queues =~ s/\n//;

    log_msg("txrx_queues is $txrx_queues.\n");
    
    if ($txrx_queues <= 0) {
	printf("Error: No TxRx queues found for new intel driver.\n");
	exit 1;
    }

    # For i = 0 to number of queues:
    #    Affinity of TX/RX queue $i gets CPU ($i * (2 if HT, 1 if no HT)) 
    #                                   % number_of_cpus
    for (my $queue = 0, my $cpu = 0; ($queue < $txrx_queues) ; $queue++) {
	# Generate the hex string for the bitmask representing this CPU
	my $cpu_bit = 1 << $cpu;
	my $cpu_hex = sprintf("%x", $cpu_bit);
	log_msg ("queue=$queue cpu=$cpu cpu_bit=$cpu_bit cpu_hex=$cpu_hex\n");
	
	# Get the IRQ number for RX queue
	my $txrx_irq=`grep "$ifname-TxRx-$queue\$" /proc/interrupts | awk -F: '{print \$1}'`;
	$txrx_irq =~ s/\n//;
	$txrx_irq =~ s/ //g;

	log_msg("txrx_irq = $txrx_irq.\n");

	# Assign CPU affinity for this IRQs
	system "echo $cpu_hex > /proc/irq/$txrx_irq/smp_affinity";

	$cpu += $ht_factor;

	if ($cpu >= $numcpus) {
	    # Must "wrap"
	    $cpu %= $numcpus;

	    if ($ht_factor > 1) {
		# Next time through, select the other CPU in a hyperthreaded 
		# pair.
		if ($cpu == 0) {
		    $cpu++;
		} else {
		    $cpu--;
		}
	    }
	}
    }
};


# Affinity assignment function for Broadcom NICs using the bnx2 driver
# or other multi-queue NICs that follow their queue naming convention.
# This strategy is similar to that for Intel drivers.  But since
# Broadcom NICs do not have separate receive and transmit queues we
# perform one affinity assignment per queue.
#
sub broadcom_func{
    my ($ifname, $numcpus, $numcores) = @_;
    my $num_queues;	# number of queues
    my $ht_factor;	# 2 if HT enabled, 1 if not

    log_msg("broadcom_func was called.\n");

    # Figure out how many queues we have
    $num_queues=`egrep "$ifname\[-.\]\{1\}" /proc/interrupts | wc -l`;
    $num_queues =~ s/\n//;

    log_msg("num_queues=$num_queues\n");

    if ($num_queues <=0) {
	printf("ERROR: No queues found for $ifname\n");
	exit 1;
    }

    if ($numcpus > $numcores) {
	$ht_factor = 2;
    } else {
	$ht_factor = 1;
    }

    log_msg("ht_factor is $ht_factor.\n");

    for (my $queue = 0, my $cpu = 0; ($queue < $num_queues) ; $queue++) {
	# Generate the hex string for the bitmask representing this CPU
	my $cpu_bit = 1 << $cpu;
	my $cpu_hex = sprintf("%x", $cpu_bit);
	log_msg ("queue=$queue cpu=$cpu cpu_bit=$cpu_bit cpu_hex=$cpu_hex\n");
	
	# Get the IRQ number for the queue
	my $irq=`egrep "$ifname\[-.fp\]*$queue\$" /proc/interrupts | awk -F: '{print \$1}'`;
	$irq =~ s/\n//;
	$irq =~ s/ //g;

	log_msg("irq = $irq.\n");

	# Assign CPU affinity for this IRQs
	system "echo $cpu_hex > /proc/irq/$irq/smp_affinity";

	$cpu += $ht_factor;
	if ($cpu >= $numcpus) {
	    # Must "wrap"
	    $cpu %= $numcpus;

	    if ($ht_factor > 1) {
		# Next time through, select the other CPU in a hyperthreaded
		# pair.
		if ($cpu == 0) {
		    $cpu++;
		} else {
		    $cpu--;
		}
	    }
	}
    }
}


# Affinity assignment function for single-quque NICs.  The strategy
# here is to just spread the interrupts of different NICs evenly
# across all CPUs.  That is the best we can do without monitoring the
# load and traffic patterns.  So we just directly map the NIC unit
# number into a CPU number.
#
sub single_func {
    my ($ifname, $numcpus, $numcores) = @_;
    my $cpu;
    use integer;

    log_msg("single_func was calledn.\n");

    $ifname =~ m/^eth(.*)$/;
    
    my $ifunit = $1;
    log_msg ("ifunit = $ifunit\n");

    # Get the IRQ number for the queue
    my $irq=`grep "$ifname" /proc/interrupts | awk -F: '{print \$1}'`;
    $irq =~ s/\n//;
    $irq =~ s/ //g;

    log_msg("irq = $irq.\n");

    # Figure out what CPU to assign it to
    if ($numcpus > $numcores) {
	# Hyperthreaded
	$cpu = (2 * $ifunit) % $numcpus;

	# every other time it wraps, add one to use the hyper-thread pair
	# of the CPU selected.
	my $use_ht = ((2 * $ifunit) / $numcpus) % 2;
	$cpu += $use_ht;
    } else {
	# Not hyperthreaded.  Map it to unit number MOD number of linux CPUs.
	$cpu = $ifunit % $numcpus;
    }

    # Generate the hex string for the bitmask representing this CPU
    my $cpu_bit = 1 << $cpu;
    my $cpu_hex = sprintf("%x", $cpu_bit);
    log_msg ("cpu=$cpu cpu_bit=$cpu_bit cpu_hex=$cpu_hex\n");

    # Assign CPU affinity for this IRQs
    system "echo $cpu_hex > /proc/irq/$irq/smp_affinity";
}

# Mapping from driver type to function that handles it.
my %driver_hash = ( 'intel' => \&intel_func,
		    'intel_new' => \&intel_new_func,
		    'broadcom' => \&broadcom_func,
		    'single' => \&single_func);

if (defined $setup_ifname) {
    # Set up automatic IRQ affinity for the named interface

    log_msg("setup $setup_ifname\n");

    my $ifname = $setup_ifname;	# shorter variable name
    my $drivername;	# Name of the NIC driver, e.g. "igb".
    my $numcpus;	# Number of Linux "cpus"
    my $numcores;	# Number of unique CPU cores
    my $driver_func;	# Pointer to fuction specific to a driver
    my $driver_style;	# Style of the driver.  Whether it is multi-queue 
			# or not, and if it is, how it names its queues.

    # Determine how many CPUs the machine has.
    $numcpus=`grep "^processor" /proc/cpuinfo | wc -l`;
    $numcpus =~ s/\n//;

    log_msg("numcpus is $numcpus\n");

    if ($numcpus == 1) {
	# Nothing to do if we only have one CPU, so just exit quietly.
	exit 0;
    }

    # Determine how many cores the machine has.  Could be less than 
    # the number of CPUs if processor supports hyperthreading.
    $numcores=`grep "^core id" /proc/cpuinfo | uniq | wc -l`;
    $numcores =~ s/\n//;

    log_msg("numcores is $numcores.\n");

    # Verify that interface exists
    if (! (-e "/proc/sys/net/ipv4/conf/$ifname")) {
	printf("Error: Interface $ifname does not exist\n");
	exit 1;
    }

    # Figure out what style of driver this NIC is using.
    my $numints=`grep $ifname /proc/interrupts | wc -l`;
    $numints =~ s/\n//;
    if ($numints > 1) {
	# It is a multiqueue NIC.  Now figure out which one.
	my $rx_queues=`grep "$ifname-rx-" /proc/interrupts | wc -l`;
	$rx_queues =~ s/\n//;
	if ($rx_queues > 0) {
	    # Driver is following the original Intel queue naming style
	    $driver_style="intel";
	} else {
	    my $rx_queues=`grep "$ifname-TxRx-" /proc/interrupts | wc -l`;
	    if ($rx_queues > 0) {
		# Driver is following the new Intel queue naming
		# style where on IRQ is used for each pair of
		# TX and RX queues
		$driver_style="intel_new";
	    } else {
		# The only other queue naming style that we have seen is the
		# one used by Broadcom NICs.
		$driver_style="broadcom";
	    }
	}
    } elsif ($numints == 1) {
	# It is a single queue NIC.
	$driver_style="single";
    } else {
	# $numints must be 0
	printf("Unable to determine IRQs for interface $ifname.\n");
	exit 0;
    }
    $driver_func = $driver_hash{$driver_style};

    &$driver_func($ifname, $numcpus, $numcores);

    exit 0;
}

printf("Must specify options.\n");
exit(1);


