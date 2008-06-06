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
use VyattaConfig;
use VyattaKeepalived;
use Getopt::Long;

use strict;
use warnings;

my $changes_file = '/var/log/vrrpd/changes';
my $conf_file = VyattaKeepalived::get_conf_file();

my %HoA_sync_groups;


sub keepalived_get_values {
    my ($intf, $path) = @_;

    my $output = '';
    my $config = new VyattaConfig;

    my $state_transition_script = VyattaKeepalived::get_state_script();
    
    $config->setLevel("$path vrrp vrrp-group");
    my @groups = $config->listNodes();
    foreach my $group (@groups) {
	my $vrrp_instance = "vyatta-$intf-$group";
	$config->setLevel("$path vrrp vrrp-group $group");
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
	my $advert_int = $config->returnValue("advertise-interval");
	if (!defined $advert_int) {
	    $advert_int = 1;
	}
	my $sync_group = $config->returnValue("sync-group");
	if (defined $sync_group && $sync_group ne "") {
	    push @{ $HoA_sync_groups{$sync_group} }, $vrrp_instance;
	}

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
	$init_state = VyattaKeepalived::vrrp_get_init_state($intf, $group, 
							    $vips[0], $preempt);
	$output .= "\tstate $init_state\n";
	$output .= "\tinterface $intf\n";
	$output .= "\tvirtual_router_id $group\n";
	$output .= "\tpriority $priority\n";
	if ($preempt eq "false") {
	    $output .= "\tnopreempt\n";
	}
	$output .= "\tadvert_int $advert_int\n";
	if (defined $auth_type) {
	    $output .= "\tauthentication {\n";
	    $output .= "\t\tauth_type $auth_type\n";
	    $output .= "\t\tauth_pass $auth_pass\n\t}\n";
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
    VyattaKeepalived::vrrp_log("saving changes file $num_changes");
    open(my $FILE, ">", $changes_file) or die "Error: write $!";
    print $FILE join("\n", @list), "\n";
    close($FILE);
}

sub vrrp_find_changes {

    my @list = ();
    my $config = new VyattaConfig;
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
		VyattaKeepalived::vrrp_log("$vrrp_status found $eth");
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
			VyattaKeepalived::vrrp_log("$vrrp_status found $eth.$vif");
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
		VyattaKeepalived::vrrp_log("Delete found $eth");
	}
	$config->setLevel("$path vif");
	my @vifs = $config->listOrigNodes();
	foreach my $vif (@vifs) {	
	    my $vif_intf = $eth . "." . $vif;
	    my $vif_path = "$path vif $vif";
	    $config->setLevel($vif_path);
	    if ($config->isDeleted("vrrp")) {
		push @list, "$eth.$vif";
		VyattaKeepalived::vrrp_log("Delete found $eth.$vif");
	    } 
	}
    }

    my $num = scalar(@list);
    VyattaKeepalived::vrrp_log("Start transation: $num changes");
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
	    VyattaKeepalived::vrrp_log("remove_from_changes [$line]");
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

    my $config = new VyattaConfig;

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
		    VyattaKeepalived::vrrp_log("skipping $vif_intf");
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


#
# main
#
my ($action, $vrrp_intf, $vrrp_group);

GetOptions("vrrp-action=s" => \$action,
	   "intf=s"        => \$vrrp_intf,
	   "group=s"       => \$vrrp_group);

if (! defined $action) {
    print "no action\n";
    exit 1;
}

if ($action eq "update") {
    VyattaKeepalived::vrrp_log("vrrp update $vrrp_intf");
    if ( ! -e $changes_file) {
	my $num_changes = vrrp_find_changes();
	if ($num_changes == 0) {
	    #
	    # Shouldn't happen, but ...
	    #
	    VyattaKeepalived::vrrp_log("unexpected 0 changes");	    
	}
    }
    my $vrrp_instances = vrrp_update_config($vrrp_intf);
    my $more_changes = remove_from_changes($vrrp_intf);
    VyattaKeepalived::vrrp_log(" instances $vrrp_instances, $more_changes");
    if ($vrrp_instances > 0 and $more_changes == 0) {
	VyattaKeepalived::restart_daemon($conf_file);
    } 
    if ($vrrp_instances == 0) {
	VyattaKeepalived::stop_daemon();
	system("rm -f $conf_file");
    }
}

if ($action eq "delete") {
    if (! defined $vrrp_intf || ! defined $vrrp_group) {
	print "must include interface & group";
	exit 1;
    }
    VyattaKeepalived::vrrp_log("vrrp delete $vrrp_intf $vrrp_group");
    my $state_file = VyattaKeepalived::get_state_file($vrrp_intf, $vrrp_group);
    system("rm -f $state_file");
    exit 0;
}

exit 0;

# end of file
