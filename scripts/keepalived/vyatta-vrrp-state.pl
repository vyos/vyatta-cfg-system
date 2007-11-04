#!/usr/bin/perl
#
# Module: vyatta-vrrp-state.pl
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
# Portions created by Vyatta are Copyright (C) 2007 Vyatta, Inc.
# All Rights Reserved.
# 
# Author: Stig Thormodsrud
# Date: October 2007
# Description: Script called on vrrp master state transition
# 
# **** End License ****
#

use lib "/opt/vyatta/share/perl5/";
use VyattaKeepalived;
use POSIX;

use strict;
use warnings;


sub snoop_for_master {
    my ($intf, $group, $vip, $file) = @_;
    
    my $cap_filt = "-f \"host 224.0.0.18 and proto VRRP\"";
    my $dis_filt = "-R \"vrrp.virt_rtr_id == $group and vrrp.ip_addr == $vip\""; 
    my $cmd = "tshark -a duration:60 -p -i$intf -c1 -T pdml $cap_filt $dis_filt";
    system("$cmd > $file 2> /dev/null");
}

sub vrrp_state_log {
    my ($state, $intf, $group) = @_;

    my $timestamp = strftime("%Y%m%d-%H:%M.%S", localtime);    
    my $file = VyattaKeepalived::get_state_file($intf, $group);
    my $time = time();
    my $line = "$time $intf $group $state $timestamp";
    open my $fh, ">", $file;
    print $fh $line;
    close $fh;
}

my $vrrp_state = $ARGV[0];
my $vrrp_intf  = $ARGV[1];
my $vrrp_group = $ARGV[2];
my $vrrp_vip   = $ARGV[3];

my $sfile = VyattaKeepalived::get_state_file($vrrp_intf, $vrrp_group);
my ($old_time, $old_intf, $old_group, $old_state, $old_ltime) = 
    VyattaKeepalived::vrrp_state_parse($sfile);
if (defined $old_state and $vrrp_state eq $old_state) {
    # 
    # restarts call the transition script even if it really hasn't
    # changed.
    #
    exit 0;
}

VyattaKeepalived::vrrp_log("$vrrp_intf $vrrp_group transition to $vrrp_state");
vrrp_state_log($vrrp_state, $vrrp_intf, $vrrp_group);
my $mfile = VyattaKeepalived::get_master_file($vrrp_intf, $vrrp_group);
if ($vrrp_state eq "backup") {
    snoop_for_master($vrrp_intf, $vrrp_group, $vrrp_vip, $mfile);
} elsif ($vrrp_state eq "master") {
    system("rm -f $mfile");
}

exit 0;

# end of file




