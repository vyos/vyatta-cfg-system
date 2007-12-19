#!/usr/bin/perl
#
# Module: vyatta-show-vrrp.pl
# 
# **** License ****
# Version: VPL 1.0
# 
# The contents of this file are subject to the Vyatta Public License
# Version 1.0 ("License"); you may not use this file except in
# compliance with the License. You may obtain a copy of the License at
# http://www.vyatta.com/vpl
# 
# Software distributed under the License is distributed on an "AS IS"
# basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
# the License for the specific language governing rights and limitations
# under the License.
# 
# This code was originally developed by Vyatta, Inc.
# Portions created by Vyatta are Copyright (C) 2005, 2006, 2007 Vyatta, Inc.
# All Rights Reserved.
# 
# Author: Stig Thormodsrud
# Date: October 2007
# Description: display vrrp info
# 
# **** End License ****
# 
use lib "/opt/vyatta/share/perl5/";
use VyattaKeepalived;

use strict;
use warnings;


sub elapse_time {
    my ($start, $stop) = @_;

    my $seconds   = $stop - $start;
    my $string    = '';
    my $secs_min  = 60;
    my $secs_hour = $secs_min  * 60;
    my $secs_day  = $secs_hour * 24;
    my $secs_week = $secs_day  * 7;
    
    my $weeks = int($seconds / $secs_week);
    if ($weeks > 0 ) {
	$seconds = int($seconds % $secs_week);
	$string .= $weeks . "w";
    }
    my $days = int($seconds / $secs_day);
    if ($days > 0) {
	$seconds = int($seconds % $secs_day);
	$string .= $days . "d";
    }
    my $hours = int($seconds / $secs_hour);
    if ($hours > 0) {
	$seconds = int($seconds % $secs_hour);
	$string .= $hours . "h";
    }
    my $mins = int($seconds / $secs_min);
    if ($mins > 0) {
	$seconds = int($seconds % $secs_min);
	$string .= $mins . "m";
    }
    $string .= $seconds . "s";

    return $string;
}

sub link_updown {
    my ($intf) = @_;

    my $status = `sudo /usr/sbin/ethtool $intf | grep Link`;
    if ($status =~ m/yes/) {
       return "up";
    }
    if ($status =~ m/no/) {
       return "down";
    }
    return "unknown";
}

sub get_master_info {
    my ($intf, $group) = @_;

    my $file = VyattaKeepalived::get_master_file($intf, $group);
    if ( -f $file) {
	my $master = `grep ip.src $file`;
	chomp $master;
	if (defined $master and $master =~ m/show=\"(\d+\.\d+\.\d+\.\d+)\"/) {
	    $master = $1;
	} else {
	    $master = "unknown";
	}
	my $priority = `grep vrrp.prio $file`;
	chomp $priority;
	if (defined $priority and $priority =~ m/show=\"(\d+)\"/) {
	    $priority = $1;
	} else {
	    $priority = "unknown";
	}
	return ($master, $priority);
    } else {
	return ("unknown", "unknown");
    }
}

sub vrrp_show {
    my ($file) = @_;

    my $now_time = time;
    my ($start_time, $intf, $group, $state, $ltime) = 
	VyattaKeepalived::vrrp_state_parse($file);
    my $link = link_updown($intf);
    if ($state eq "master" || $state eq "backup" || $state eq "fault") {
	my ($primary_addr, $priority, $preempt, $advert_int, $auth_type, 
	    @vips) = VyattaKeepalived::vrrp_get_config($intf, $group);
	print "Physical interface: $intf, Address $primary_addr\n";
	print "  Interface state: $link, Group $group, State: $state\n";
	print "  Priority: $priority, Advertisement interval: $advert_int, ";
	print "Authentication type: $auth_type\n";
	my $vip_count = scalar(@vips);
	my $string = "  Preempt: $preempt, VIP count: $vip_count, VIP: ";
	my $strlen = length($string);
	print $string;
	foreach my $vip (@vips) {
	    if ($vip_count != scalar(@vips)) {
		print " " x $strlen;
	    }
	    print "$vip\n";
	    $vip_count--;
	}
	if ($state eq "master") {
	    print "  Master router: $primary_addr\n";
	} elsif ($state eq "backup") {
	    my ($master_rtr, $master_prio) = get_master_info($intf, $group);
	    print "  Master router: $master_rtr, ";
            print "Master Priority: $master_prio\n";
	}
    } else {
	print "Physical interface $intf, State: unknown\n";
    }
    my $elapsed = elapse_time($start_time, $now_time);
    print "  Last transition: $elapsed\n\n";
}

#
# main
#    
my $intf  = "eth";
my $group = "all";
if ($#ARGV == 0) {
    $intf = $ARGV[0];
}
if ($#ARGV == 1) {
    $group = $ARGV[1];
}

if (!VyattaKeepalived::is_running()) {
    print "VRRP isn't running\n";
    exit 1;
}

my @state_files = VyattaKeepalived::get_state_files($intf, $group);
foreach my $state_file (@state_files) {
    vrrp_show($state_file);
}

exit 0;

#end of file
