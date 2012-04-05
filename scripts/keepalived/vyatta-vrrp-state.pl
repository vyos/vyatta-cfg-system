#!/usr/bin/perl
#
# Module: vyatta-vrrp-state.pl
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
# Portions created by Vyatta are Copyright (C) 2007 Vyatta, Inc.
# All Rights Reserved.
# 
# Author: Stig Thormodsrud
# Date: October 2007
# Description: Script called on vrrp master state transition
# 
# **** End License ****
#

use strict;
use warnings;

use lib "/opt/vyatta/share/perl5/";
use Vyatta::Keepalived;
use POSIX;

sub vrrp_state_log {
    my ($state, $intf, $group) = @_;

    my $timestamp = strftime("%Y%m%d-%H:%M.%S", localtime);    
    my $file = Vyatta::Keepalived::get_state_file($intf, $group);
    my $time = time();
    my $line = "$time $intf $group $state $timestamp";
    open my $fh, ">", $file;
    print $fh $line;
    close $fh;
}

my $vrrp_state = $ARGV[0];
my $vrrp_intf  = $ARGV[1];
my $vrrp_group = $ARGV[2];
# transition interface will contain the vmac interface
# when one is present and the vrrp interface when one is not
my $transition_intf = $ARGV[3]; 
my $vrrp_transitionscript = $ARGV[4];
my @vrrp_vips;
foreach my $arg (5 .. $#ARGV) {
    push @vrrp_vips, $ARGV[$arg];
}

my $sfile = Vyatta::Keepalived::get_state_file($vrrp_intf, $vrrp_group);
my ($old_time, $old_intf, $old_group, $old_state, $old_ltime) = 
    Vyatta::Keepalived::vrrp_state_parse($sfile);
if (defined $old_state and $vrrp_state eq $old_state) {
    # 
    # restarts call the transition script even if it really hasn't
    # changed.
    #
    Vyatta::Keepalived::vrrp_log("$vrrp_intf $vrrp_group same - $vrrp_state");
    exit 0;
}

Vyatta::Keepalived::vrrp_log("$vrrp_intf $vrrp_group transition to $vrrp_state");
vrrp_state_log($vrrp_state, $vrrp_intf, $vrrp_group);
if ($vrrp_state eq 'backup') {
    # comment out for now, too expensive with lots of vrrp's at boot
    # Vyatta::Keepalived::snoop_for_master($vrrp_intf, $vrrp_group, 
    #                                      $vrrp_vips[0], 60);
    # Filter traffic incoming to the vmac interface when in backup state
    # Delete the rule then add it to insure that we don't get duplicates
} elsif ($vrrp_state eq 'master') {
    #
    # keepalived will send gratuitous arp requests on master transition
    # but some hosts do not update their arp cache for gratuitous arp 
    # requests.  Some of those host do respond to gratuitous arp replies
    # so here we will send 5 gratuitous arp replies also.
    #
    unless ($transition_intf =~ m/\w+v\d+/){
      foreach my $vip (@vrrp_vips) {
	system("/usr/bin/arping -A -c5 -I $vrrp_intf $vip");
      }
    }

    #
    # remove the old master file since we are now master
    #
    my $mfile = Vyatta::Keepalived::get_master_file($vrrp_intf, $vrrp_group);
    system("rm -f $mfile");
}

if (!($vrrp_transitionscript eq 'null')){
    exec("$vrrp_transitionscript $vrrp_state $vrrp_intf $vrrp_group");
}

exit 0;

# end of file




