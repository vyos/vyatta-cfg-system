#!/usr/bin/perl
#
# Module: vyatta-keepalived.pl
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
# Description: Script to glue vyatta cli to keepalived daemon
# 
# **** End License ****
#

use lib "/opt/vyatta/share/perl5/";
use Vyatta::Config;
use Vyatta::Keepalived;
use Vyatta::TypeChecker;
use Vyatta::Interface;
use Vyatta::Misc;
use Getopt::Long;

use strict;
use warnings;

my ($conf_file, $changes_file);
my %HoA_sync_groups;

sub validate_source_addr {
    my ($ifname, $source_addr) = @_;

    my @ipaddrs;
    if (defined $source_addr) {
	my %config_ipaddrs;
	my @ipaddrs = Vyatta::Misc::getInterfacesIPadresses('all');
	foreach my $ip (@ipaddrs) {
	    if ($ip =~ /^([\d.]+)\/([\d.]+)$/) { # strip /mask
		$config_ipaddrs{$1} = 1;
	    }
	}
	if (!defined $config_ipaddrs{$source_addr}) {
	    print "hello-source-address [$source_addr] must be configured on" .
		" some interface\n";
	    exit 1;
	}
	return;
    }
    # if the hello-source-address wasn't configured, check that the
    # interface has an IPv4 address configured on it.
    my $intf = new Vyatta::Interface($ifname);
    @ipaddrs = $intf->address(4);
    if (scalar(@ipaddrs) < 1) {
	print "must configure either a primary address on [$ifname] or" .
	    " a hello-source-address\n";
	exit 1;
    }
    return;
}

sub keepalived_get_values {
    my ($intf, $path) = @_;

    my $output = '';
    my $config = new Vyatta::Config;

    my $state_transition_script = get_state_script();
    
    $config->setLevel("$path vrrp vrrp-group");
    my @groups = $config->listNodes();
    foreach my $group (@groups) {
	my $vrrp_instance = "vyatta-$intf-$group";
	$config->setLevel("$path vrrp vrrp-group $group");
	if ($config->exists("disable")) {
	    vrrp_log("$vrrp_instance disabled - skipping");
	    my $state_file = get_state_file($intf, $group);
	    system("rm -f $state_file");
	    next;
	}
	my @vips = $config->returnValues("virtual-address");
	my $num_vips = scalar(@vips);
	if ($num_vips == 0) {
	    print "must define a virtual-address for vrrp-group $group\n";
	    exit 1;
	}
	if ($num_vips > 20) {
	    print "can not set more than 20 VIPs per group\n";
	    exit 1;
	}
	my $priority = $config->returnValue("priority");
	if (!defined $priority) {
	    $priority = 1;
	}
	my $preempt = $config->returnValue("preempt");
	if (!defined $preempt) {
	    $preempt = "true";
	}
	my $preempt_delay = $config->returnValue("preempt-delay");
	if (defined $preempt_delay and $preempt eq "false") {
	    print "Warning: preempt delay is ignored when preempt=false\n";
	}
	my $advert_int = $config->returnValue("advertise-interval");
	if (!defined $advert_int) {
	    $advert_int = 1;
	}
	my $sync_group = $config->returnValue("sync-group");
	if (defined $sync_group && $sync_group ne "") {
	    push @{ $HoA_sync_groups{$sync_group} }, $vrrp_instance;
	}
	my $hello_source_addr = $config->returnValue("hello-source-address");
	validate_source_addr($intf, $hello_source_addr);

	$config->setLevel("$path vrrp vrrp-group $group authentication");
	my $auth_type = $config->returnValue("type");
	my $auth_pass;
	if (defined $auth_type) {
	    $auth_type = "PASS" if $auth_type eq "simple";
	    $auth_type = uc($auth_type);
	    $auth_pass = $config->returnValue("password");
	    if (! defined $auth_pass) {
		print "vrrp authentication password not set";
		exit 1;
	    }
	}

	$config->setLevel("$path vrrp vrrp-group $group run-transition-scripts");
        my $run_backup_script = $config->returnValue("backup");
        if(!defined $run_backup_script){
           $run_backup_script = "null";
        }
        my $run_fault_script = $config->returnValue("fault");
        if(!defined $run_fault_script){
           $run_fault_script = "null";
        }
        my $run_master_script = $config->returnValue("master");
        if(!defined $run_master_script){
           $run_master_script = "null";
        }

	$output  .= "vrrp_instance $vrrp_instance \{\n";
	my $init_state;
	$init_state = vrrp_get_init_state($intf, $group, 
							    $vips[0], $preempt);
	$output .= "\tstate $init_state\n";
	$output .= "\tinterface $intf\n";
	$output .= "\tvirtual_router_id $group\n";
	$output .= "\tpriority $priority\n";
	if ($preempt eq "false") {
	    $output .= "\tnopreempt\n";
	}
	if (defined $preempt_delay) {
	    $output .= "\tpreempt_delay $preempt_delay\n";
	}
	$output .= "\tadvert_int $advert_int\n";
	if (defined $auth_type) {
	    $output .= "\tauthentication {\n";
	    $output .= "\t\tauth_type $auth_type\n";
	    $output .= "\t\tauth_pass $auth_pass\n\t}\n";
	}
	if (defined $hello_source_addr) {
	    $output .= "\tmcast_src_ip $hello_source_addr\n";
	}
	$output .= "\tvirtual_ipaddress \{\n";
	foreach my $vip (@vips) {
	    $output .= "\t\t$vip\n";
	}
	$output .= "\t\}\n";
	$output .= "\tnotify_master \"$state_transition_script master ";
	$output .=     "$intf $group $run_master_script @vips\" \n";
	$output .= "\tnotify_backup \"$state_transition_script backup ";
        $output .=     "$intf $group $run_backup_script @vips\" \n";
	$output .= "\tnotify_fault \"$state_transition_script fault ";
	$output .=     "$intf $group $run_fault_script @vips\" \n";
	$output .= "\}\n\n";
    }

    return $output;
}

sub vrrp_get_sync_groups {
    
    my $output = "";
   
    foreach my $sync_group ( keys %HoA_sync_groups) {
	$output .= "vrrp_sync_group $sync_group \{\n\tgroup \{\n";
	foreach my $vrrp_instance ( 0 .. $#{ $HoA_sync_groups{$sync_group} } ) {
	    $output .= "\t\t$HoA_sync_groups{$sync_group}[$vrrp_instance]\n";
	}
	$output .= "\t\}\n\}\n";
    }
    
    return $output;
}

sub vrrp_read_changes {
    my @lines = ();
    open(my $FILE, "<", $changes_file) or die "Error: read $!";
    @lines = <$FILE>;
    close($FILE);
    chomp @lines;
    return @lines;
}

sub vrrp_save_changes {
    my @list = @_;

    my $num_changes = scalar(@list);
    vrrp_log("saving changes file $num_changes");
    open(my $FILE, ">", $changes_file) or die "Error: write $!";
    print $FILE join("\n", @list), "\n";
    close($FILE);
}

sub vrrp_find_changes {

    my @list = ();
    my $config = new Vyatta::Config;
    my $vrrp_instances = 0;

    $config->setLevel("interfaces ethernet");
    my @eths = $config->listNodes();
    foreach my $eth (@eths) {
	my $path = "interfaces ethernet $eth";
	$config->setLevel($path);
	if ($config->exists("vrrp")) {
	    my %vrrp_status_hash = $config->listNodeStatus("vrrp");
	    my ($vrrp, $vrrp_status) = each(%vrrp_status_hash);
	    if ($vrrp_status ne "static") {
		push @list, $eth;
		vrrp_log("$vrrp_status found $eth");
	    }
	}
	if ($config->exists("vif")) {
	    my $path = "interfaces ethernet $eth vif";
	    $config->setLevel($path);
	    my @vifs = $config->listNodes();
	    foreach my $vif (@vifs) {	
		my $vif_intf = $eth . "." . $vif;
	    	my $vif_path = "$path $vif";
		$config->setLevel($vif_path);
		if ($config->exists("vrrp")) {
		    my %vrrp_status_hash = $config->listNodeStatus("vrrp");
		    my ($vrrp, $vrrp_status) = each(%vrrp_status_hash);
		    if ($vrrp_status ne "static") {
			push @list, "$eth.$vif";
			vrrp_log("$vrrp_status found $eth.$vif");
		    }
		}
	    }
	}
    }

    #
    # Now look for deleted from the origin tree
    #
    $config->setLevel("interfaces ethernet");
    @eths = $config->listOrigNodes();
    foreach my $eth (@eths) {
	my $path = "interfaces ethernet $eth";
	$config->setLevel($path);
	if ($config->isDeleted("vrrp")) {
		push @list, $eth;
		vrrp_log("Delete found $eth");
	}
	$config->setLevel("$path vif");
	my @vifs = $config->listOrigNodes();
	foreach my $vif (@vifs) {	
	    my $vif_intf = $eth . "." . $vif;
	    my $vif_path = "$path vif $vif";
	    $config->setLevel($vif_path);
	    if ($config->isDeleted("vrrp")) {
		push @list, "$eth.$vif";
		vrrp_log("Delete found $eth.$vif");
	    } 
	}
    }

    my $num = scalar(@list);
    vrrp_log("Start transation: $num changes");
    if ($num) {
	vrrp_save_changes(@list);
    }
    return $num;
}

sub remove_from_changes {
    my $intf = shift;

    my @lines = vrrp_read_changes();
    if (scalar(@lines) < 1) {
	#
	# we shouldn't get to this point, but try to handle it if we do
	#
	system("rm -f $changes_file");
	return 0;
    }
    my @new_lines = ();
    foreach my $line (@lines) {
	if ($line =~ /$intf$/) {
	    vrrp_log("remove_from_changes [$line]");
	} else {
	    push @new_lines, $line;
	}
    }

    my $num_changes = scalar(@new_lines);
    if ($num_changes > 0) {
	vrrp_save_changes(@new_lines);
    } else {
	system("rm -f $changes_file");
    }
    return $num_changes;
}

sub vrrp_update_config {
    my ($intf) = @_;

    my $date = localtime();
    my $output = "#\n# autogenerated by $0 on $date\n#\n\n";

    my $config = new Vyatta::Config;

    $config->setLevel("interfaces ethernet");
    my @eths = $config->listNodes();
    my $vrrp_instances = 0;
    foreach my $eth (@eths) {
	my $path = "interfaces ethernet $eth";
	$config->setLevel($path);
	if ($config->exists("vrrp")) {
	    $output .= keepalived_get_values($eth, $path);
	    $vrrp_instances++;
	}
	if ($config->exists("vif")) {
	    my $path = "interfaces ethernet $eth vif";
	    $config->setLevel($path);
	    my @vifs = $config->listNodes();
	    foreach my $vif (@vifs) {
		#
		# keepalived gets real grumpy with interfaces that don't 
		# exist, so skip vlans that haven't been instantiated 
		# yet (typically occurs at boot up).
		#
		my $vif_intf = $eth . "." . $vif;
		if (!(-d "/sys/class/net/$vif_intf")) {
		    vrrp_log("skipping $vif_intf");
		    next;
		}
		my $vif_path = "$path $vif";
		$config->setLevel($vif_path);
		if ($config->exists("vrrp")) {
		    $output .= keepalived_get_values($vif_intf, $vif_path);
		    $vrrp_instances++;
		}
	    }
	}
    }
      
    if ($vrrp_instances > 0) {
	my $sync_groups = vrrp_get_sync_groups();
	if (defined $sync_groups && $sync_groups ne "") {
	    $output = $sync_groups . $output;
	}
	keepalived_write_file($conf_file, $output);
    } 
    return $vrrp_instances;
}

sub keepalived_write_file {
    my ($file, $data) = @_;

    open(my $fh, '>', $file) || die "Couldn't open $file - $!";
    print $fh $data;
    close $fh;
}

sub list_vrrp_intf {
    my $config = new Vyatta::Config;
    my @intfs = ();

    $config->setLevel("interfaces ethernet");
    my @eths = $config->listOrigNodes();
    foreach my $eth (@eths) {
	my $path = "interfaces ethernet $eth";
	$config->setLevel($path);
	push @intfs, $eth if $config->existsOrig("vrrp");
	if ($config->existsOrig("vif")) {
	    my $path = "interfaces ethernet $eth vif";
	    $config->setLevel($path);
	    my @vifs = $config->listOrigNodes();
	    foreach my $vif (@vifs) {	
		my $vif_intf = $eth . "." . $vif;
	    	my $vif_path = "$path $vif";
		$config->setLevel($vif_path);
		push @intfs, $vif_intf if $config->existsOrig("vrrp");
	    }
	}
    }
    return @intfs;
}

sub list_vrrp_group {
    my ($name) = @_;

    my $config = new Vyatta::Config;
    my $path   = "interfaces ethernet $name";
    if ($name =~ /(eth\d+)\.(\d+)/) {
	$path = "interfaces ethernet $1 vif $2"; 
    }
    $path .= " vrrp vrrp-group";
    $config->setLevel($path);
    my @groups = $config->listOrigNodes();
    return @groups;
}


#
# main
#
my ($action, $vrrp_intf, $vrrp_group, $vrrp_vip);

GetOptions("vrrp-action=s" => \$action,
	   "intf=s"        => \$vrrp_intf,
	   "group=s"       => \$vrrp_group,
           "vip=s"         => \$vrrp_vip);

if (! defined $action) {
    print "no action\n";
    exit 1;
}

if ($action eq "update") {
    $changes_file = get_changes_file();
    $conf_file = get_conf_file();
    vrrp_log("vrrp update $vrrp_intf");
    if ( ! -e $changes_file) {
	my $num_changes = vrrp_find_changes();
	if ($num_changes == 0) {
	    #
	    # Shouldn't happen, but ...
	    #
	    vrrp_log("unexpected 0 changes");	    
	}
    }
    my $vrrp_instances = vrrp_update_config($vrrp_intf);
    my $more_changes = remove_from_changes($vrrp_intf);
    vrrp_log(" instances $vrrp_instances, $more_changes");
    if ($vrrp_instances > 0 and $more_changes == 0) {
	restart_daemon($conf_file);
    } 
    if ($vrrp_instances == 0) {
	stop_daemon();
	system("rm -f $conf_file");
    }
}

if ($action eq "delete") {
    if (! defined $vrrp_intf || ! defined $vrrp_group) {
	print "must include interface & group";
	exit 1;
    }
    vrrp_log("vrrp delete $vrrp_intf $vrrp_group");
    my $state_file = get_state_file($vrrp_intf, $vrrp_group);
    system("rm -f $state_file");
    exit 0;
}

if ($action eq "check-vip") {
    if (! defined $vrrp_vip) {
	print "must include the virtual-address to check";
	exit 1;
    }
    my $rc = 1;
    if ($vrrp_vip =~ /\//) {
	$rc = Vyatta::TypeChecker::validateType('ipv4net', $vrrp_vip, 1);
    } else {
	$rc = Vyatta::TypeChecker::validateType('ipv4', $vrrp_vip, 1);
    }
    exit 1 if ! $rc;
    exit 0;
}

if ($action eq "list-vrrp-intf") {
    my @intfs = list_vrrp_intf();
    print join(' ', @intfs);
    exit 0;
}

if ($action eq "list-vrrp-group") {
    if (! defined $vrrp_intf) {
	print "must include interface\n";
	exit 1;
    }
    my @groups = list_vrrp_group($vrrp_intf);
    print join(' ', @groups);
    exit 0;
}

exit 0;

# end of file
