#
# Module: VyattaKeepalived.pm
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
# Description: Common keepalived definitions/funcitions
# 
# **** End License ****
#
package VyattaKeepalived;

use VyattaConfig;
use POSIX;

use strict;
use warnings;

my $daemon           = '/usr/sbin/keepalived';
my $keepalived_conf  = '/etc/keepalived/keepalived.conf';
my $sbin_dir         = '/opt/vyatta/sbin';
my $state_transition = "$sbin_dir/vyatta-vrrp-state.pl";
my $keepalived_pid   = '/var/run/keepalived_vrrp.pid';
my $state_dir        = '/var/log/vrrpd';
my $vrrp_log         = "$state_dir/vrrp.log";


sub vrrp_log {
    my $timestamp = strftime("%Y%m%d-%H:%M.%S", localtime);
    open my $fh, ">>", $vrrp_log;
    print $fh "$timestamp: ", @_ , "\n";
    close $fh;
}

sub is_running {
    if (-f $keepalived_pid) {
	my $pid = `cat $keepalived_pid`;
	chomp $pid;
	my $ps = `ps -p $pid -o comm=`;

	if (defined($ps) && $ps ne "") {
	    return 1;
	} 
    }
    return 0;
}

sub start_daemon {
    my ($conf) = @_;

    my $cmd  = "$daemon --vrrp --log-facility 7 --log-detail --dump-conf";
       $cmd .= " --use-file $conf";
    system($cmd);
    vrrp_log("start_daemon");
}

sub stop_daemon {
    if (is_running()) {
	my $pid = `cat $keepalived_pid`;
	system("kill $pid");
	vrrp_log("stop_daemon");
    } else {
	vrrp_log("stop daemon called while not running");
    }
}

sub restart_daemon {
    my ($conf) = @_;

    if (VyattaKeepalived::is_running()) {
	my $pid = `cat $keepalived_pid`;
	chomp $pid;
	system("kill -1 $pid");
	vrrp_log("restart_deamon");
    } else {
	start_daemon($conf);	
    }    
}

sub get_conf_file {
    return $keepalived_conf;
}

sub get_state_script {
    return $state_transition;
}

sub get_state_file {
    my ($vrrp_intf, $vrrp_group) = @_;

    my $file = "$state_dir/vrrpd_" . "$vrrp_intf" . "_" . "$vrrp_group.state";
    return $file;
}

sub get_master_file {
    my ($vrrp_intf, $vrrp_group) = @_;

    my $file = "$state_dir/vrrpd_" . "$vrrp_intf" . "_" . "$vrrp_group.master";
    return $file;
}

sub get_state_files {
    my ($intf, $group) = @_;

    # todo: fix sorting for ethX > 9
    my @state_files;
    my $LS;
    if ($group eq "all") {
	open($LS,"ls $state_dir |grep '^vrrpd_$intf.*\.state\$' | sort |");
    } else {
	my $intf_group = $intf . "_" . $group . ".state";
	open($LS,
	     "ls $state_dir |grep '^vrrpd_$intf_group\$' | sort |");
    }
    @state_files = <$LS>;
    close($LS);
    foreach my $i (0 .. $#state_files) {
	$state_files[$i] = "$state_dir/$state_files[$i]";
    }
    chomp  @state_files;
    return @state_files;
}

sub vrrp_get_config {
    my ($intf, $group) = @_;

    my $path;
    my $config = new VyattaConfig;
    
    if ($intf =~ m/(eth\d+)\.(\d+)/) {
	$path = "interfaces ethernet $1 vif $2";
    } else {
	$path = "interfaces ethernet $intf";
    }

    $config->setLevel($path);
    my $primary_addr = $config->returnOrigValue("address"); 
    if (!defined $primary_addr) {
	$primary_addr = "0.0.0.0";
    }

    if ($primary_addr =~ m/(\d+\.\d+\.\d+\.\d+)\/\d+/) {
	$primary_addr = $1;
    }

    $config->setLevel("$path vrrp vrrp-group $group");
    my @vips = $config->returnOrigValues("virtual-address");
    my $priority = $config->returnOrigValue("priority");
    if (!defined $priority) {
	$priority = 1;
    }
    my $preempt = $config->returnOrigValue("preempt");
    if (!defined $preempt) {
	$preempt = "true";
    }
    my $advert_int = $config->returnOrigValue("advertise-interval");
    if (!defined $advert_int) {
	$advert_int = 1;
    }
    $config->setLevel("$path vrrp vrrp-group $group authentication");
    my $auth_type = $config->returnOrigValue("type");
    if (!defined $auth_type) {
	$auth_type = "none";
    } 

    return ($primary_addr, $priority, $preempt, $advert_int, $auth_type, @vips);
}

sub vrrp_state_parse {
    my ($file) = @_;

    if ( -f $file) {
	my $line = `cat $file`;
	chomp $line;
	my ($start_time, $intf, $group, $state, $ltime) = split(' ', $line);
	return ($start_time, $intf, $group, $state, $ltime);
    } else {
	return undef;
    }
}

#end of file
