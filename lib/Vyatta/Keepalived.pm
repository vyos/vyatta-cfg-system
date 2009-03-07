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
# Portions created by Vyatta are Copyright (C) 2007-2009 Vyatta, Inc.
# All Rights Reserved.
# 
# Author: Stig Thormodsrud
# Date: October 2007
# Description: Common keepalived definitions/funcitions
# 
# **** End License ****
#
package Vyatta::Keepalived;
our @EXPORT = qw(get_conf_file get_state_script get_state_file 
                 vrrp_log vrrp_get_init_state get_changes_file
                 start_daemon restart_daemon stop_daemon
                 vrrp_get_config);
use base qw(Exporter);

use Vyatta::Config;
use POSIX;

use strict;
use warnings;

my $daemon           = '/usr/sbin/keepalived';
my $keepalived_conf  = '/etc/keepalived/keepalived.conf';
my $sbin_dir         = '/opt/vyatta/sbin';
my $state_transition = "$sbin_dir/vyatta-vrrp-state.pl";
my $keepalived_pid   = '/var/run/keepalived_vrrp.pid';
my $state_dir        = '/var/run/vrrpd';
my $vrrp_log         = "$state_dir/vrrp.log";
my $changes_file     = "$state_dir/changes";

sub vrrp_log {
    my $timestamp = strftime("%Y%m%d-%H:%M.%S", localtime);
    open my $fh, '>>', $vrrp_log
	or die "Can't open $vrrp_log:$!";
    print $fh "$timestamp: ", @_ , "\n";
    close $fh;
}

sub is_running {
    if (-f $keepalived_pid) {
	my $pid = `cat $keepalived_pid`;
	$pid =~ s/\s+$//;  # chomp doesn't remove nl
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
       $cmd .= " --use-file $conf --vyatta-workaround";
    system($cmd);
    vrrp_log("start_daemon");
}

sub stop_daemon {
    if (is_running()) {
	my $pid = `cat $keepalived_pid`;
	$pid =~ s/\s+$//;  # chomp doesn't remove nl
	system("kill $pid");
	vrrp_log("stop_daemon");
    } else {
	vrrp_log("stop daemon called while not running");
    }
}

sub restart_daemon {
    my ($conf) = @_;

    if (is_running()) {
	my $pid = `cat $keepalived_pid`;
	$pid =~ s/\s+$//;  # chomp doesn't remove nl
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

sub get_changes_file {
    system("mkdir $state_dir") if ! -d $state_dir;
    return $changes_file;
}

sub get_state_file {
    my ($vrrp_intf, $vrrp_group) = @_;

    system("mkdir $state_dir") if ! -d $state_dir;
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
    my $config = new Vyatta::Config;
    
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
	$primary_addr = $1;  # strip /mask
    }

    $config->setLevel("$path vrrp vrrp-group $group");
    my $source_addr = $config->returnOrigValue("hello-source-address"); 
    $primary_addr = $source_addr if defined $source_addr;

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

sub snoop_for_master {
    my ($intf, $group, $vip, $timeout) = @_;

    my ($cap_filt, $dis_filt, $options, $cmd);

    my $file = get_master_file($intf, $group);

    # remove mask if vip has one
    if ($vip =~ /([\d.]+)\/\d+/) {
	$vip = $1;
    }

    #
    # set up common tshark parameters
    #
    $cap_filt = "-f \"host 224.0.0.18";
    $dis_filt = "-R \"vrrp.virt_rtr_id == $group and vrrp.ip_addr == $vip\""; 
    $options  = "-a duration:$timeout -p -i$intf -c1 -T pdml";

    my $auth_type = (vrrp_get_config($intf, $group))[4];
    if (lc($auth_type) ne "ah") {
	#
	# the vrrp group is the 2nd byte in the vrrp header
	#
	$cap_filt .= " and proto VRRP and vrrp[1:1] = $group\"";
	$cmd      = "tshark $options $cap_filt $dis_filt";
	system("$cmd > $file 2> /dev/null");
    } else {
	#
	# if the vrrp group is using AH authentication, then the proto will be
	# AH (0x33) instead of VRRP (0x70). So try snooping for AH and 
	# look for the vrrp group at byte 45 (ip_header=20, ah=24)
	#
	$cap_filt .= " and proto 0x33 and ip[45:1] = $group\"";
	$cmd      = "tshark $options $cap_filt $dis_filt";
	system("$cmd > $file 2> /dev/null");
    }
}

sub vrrp_state_parse {
    my ($file) = @_;

    $file =~ s/\s+$//;  # chomp doesn't remove nl
    if ( -f $file) {
	my $line = `cat $file`;
	chomp $line;
	my ($start_time, $intf, $group, $state, $ltime) = split(' ', $line);
	return ($start_time, $intf, $group, $state, $ltime);
    } else {
	return undef;
    }
}

sub vrrp_get_init_state {
    my ($intf, $group, $vips, $preempt) = @_;

    my $init_state;
    if (is_running()) {
	my @state_files = get_state_files($intf, $group);
	chomp @state_files;
	if (scalar(@state_files) > 0) {
	    my ($start_time, $f_intf, $f_group, $state, $ltime) = 
		vrrp_state_parse($state_files[0]);
	    if ($state eq "master") {
		$init_state = 'MASTER';
	    } else {
		$init_state = 'BACKUP';
	    }
	    return $init_state;
	}
	# fall through to logic below
    } 

    if ($preempt eq "false") {
	$init_state = 'BACKUP';
    } else {
	$init_state = 'MASTER';
    }

    return $init_state;
}

1;
#end of file
