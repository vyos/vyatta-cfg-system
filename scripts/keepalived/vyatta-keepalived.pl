#!/usr/bin/perl
#
# Module: vyatta-keepalived.pl
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
	if (scalar(@vips) == 0) {
	    print "must define a virtual-address for vrrp-group $group\n";
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

	$output  .= "vrrp_instance $vrrp_instance \{\n";
	if ($preempt eq "false") {
	    $output .= "\tstate BACKUP\n";
	} else {
	    $output .= "\tstate MASTER\n";
	}
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
	$output .= "\tnotify_master ";
	$output .= "\"$state_transition_script master $intf $group @vips\" \n";
	$output .= "\tnotify_backup ";
	$output .= "\"$state_transition_script backup $intf $group @vips\" \n";
	$output .= "\tnotify_fault  ";
	$output .= "\"$state_transition_script fault  $intf $group @vips\" \n";
	$output .= "\}\n";
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

sub vrrp_update_config {
    my $output;

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
	my $conf_file = VyattaKeepalived::get_conf_file();
	keepalived_write_file($conf_file, $output);
	VyattaKeepalived::restart_daemon($conf_file);
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
    my $vrrp_instances = vrrp_update_config();
    VyattaKeepalived::vrrp_log("vrrp update $vrrp_intf $vrrp_instances");
    if ($vrrp_instances == 0) {
	VyattaKeepalived::stop_daemon();
    }
}

if ($action eq "delete") {
    if (! defined $vrrp_intf || ! defined $vrrp_group) {
	print "must include interface & group";
	exit 1;
    }
    my $state_file = VyattaKeepalived::get_state_file($vrrp_intf, $vrrp_group);
    system("rm -f $state_file");
    VyattaKeepalived::vrrp_log("vrrp delete $vrrp_intf $vrrp_group");
    exit 0;
}

exit 0;

# end of file




