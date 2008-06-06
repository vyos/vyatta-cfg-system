#!/usr/bin/perl
#
# Module: vyatta-clear-vrrp.pl
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
# Date: May 2008
# Description: Script to clear vrrp
# 
# **** End License ****
#

use lib "/opt/vyatta/share/perl5/";
use VyattaKeepalived;
use Getopt::Long;
use Sys::Syslog qw(:standard :macros);

use strict;
use warnings;

my $conf_file = VyattaKeepalived::get_conf_file();


sub keepalived_write_file {
    my ($file, $data) = @_;

    open(my $fh, '>', $file) || die "Couldn't open $file - $!";
    print $fh $data;
    close $fh;
}

sub set_instance_inital_state {
    my ($instance, $init) = @_;
    
    if ($init eq "MASTER" and $instance =~ /state \s+ BACKUP/ix) {
	if ($instance !~ s/state \s+ BACKUP/state MASTER/ix) {
	    print "Error: unable to replace BACKUP/MASTER\n";
	}
    } elsif ($init eq "BACKUP" and $instance =~ /state \s+ MASTER/ix) {
	if ($instance !~ s/state \s+ MASTER/state BACKUP/ix) {
	    print "Error: unable to replace MASTER/BACKUP\n";
	}
    }
    return $instance;
}

my $brace_block;

sub vrrp_extract_instance {
    my ($conf, $instance) = @_;
    
    #
    # regex to find a balanced group of squiggly braces  {{{ }}}
    #
    $brace_block = qr/
        \{                         # 1st brace
           (
             [^\{\}]+              # anything but brace
             |                     # or
             (??{ $brace_block })  # another brace_block 
            )*
        \}                         # matching brace
      /x;

    # 
    # regex to match instance:
    #
    # vrrp_instance vyatta-eth1.100-15 {
    #    state MASTER
    #    interface eth1
    #    virtual_router_id 15
    #    virtual_ipaddress {
    #            1.1.1.1
    #    }
    # }
    #
    my $instance_regex = qr/(vrrp_instance \s+ $instance \s+ $brace_block)/x;

    #
    # replace the instance with nothing
    #
    my $match_instance;
    if ($conf =~ s/($instance_regex)//) {
	$match_instance = $1;
    } else {
	return ($conf, undef);
    }

    return ($conf, $match_instance);
}

sub get_vrrp_intf_group {
    my @array;

    #
    # return an array of hashes that contains all the intf/group pairs
    #

    my $config = new VyattaConfig;
    $config->setLevel("interfaces ethernet");
    my @eths = $config->listOrigNodes();
    foreach my $eth (@eths) {
	my $path = "interfaces ethernet $eth";
	$config->setLevel($path);
	if ($config->existsOrig("vrrp")) {
	    $path = "$path vrrp vrrp-group";
	    $config->setLevel($path);
	    my @groups = $config->listOrigNodes();
	    foreach my $group (@groups) {
		my %hash;
		$hash{'intf'}  = $eth;
		$hash{'group'} = $group;
		$hash{'path'}  = "$path $group";
		push @array, {%hash};
	    }
	}
	
	$path = "interfaces ethernet $eth";
	$config->setLevel($path);
	if ($config->existsOrig("vif")) {
	    my $path = "$path vif";
	    $config->setLevel($path);
	    my @vifs = $config->listOrigNodes();
	    foreach my $vif (@vifs) {
		my $vif_intf = $eth . "." . $vif;
	    	my $vif_path = "$path $vif";
		$config->setLevel($vif_path);
		if ($config->existsOrig("vrrp")) {
		    $vif_path = "$vif_path vrrp vrrp-group";		    
		    $config->setLevel($vif_path);
		    my @groups = $config->listOrigNodes();
		    foreach my $group (@groups) {
			my %hash;
			$hash{'intf'}  = $vif_intf;
			$hash{'group'} = $group;
			$hash{'path'}  = "$path $group";
			push @array, {%hash};
		    }
		}   
	    }
	}
    }

    return @array;
}

sub set_inital_state {
    my $conf = shift;

    my $new_conf = '';

    #
    # find all intf/groups, extract instance, set init state
    #
    my @vrrp_instances = get_vrrp_intf_group();

    foreach my $hash (@vrrp_instances) {
	my $intf  = $hash->{'intf'};
	my $group = $hash->{'group'};
	my $instance = "vyatta-" . "$intf" . "-" . "$group";
	my ($tmp_conf, $match_instance) = 
	    vrrp_extract_instance($conf, $instance); 
	if (defined $match_instance) {
	    my $init = VyattaKeepalived::vrrp_get_init_state($intf, $group, 
							     "", "false");
	    $match_instance = set_instance_inital_state($match_instance, $init);
	    $new_conf .= $match_instance . "\n\n";
	} 
    }

    return $new_conf;
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

openlog($0, "", LOG_USER);
my $login = getlogin();

#
# clear_process
#
if ($action eq "clear_process") {
    syslog("warning", "clear vrrp process requested by $login");
    if (VyattaKeepalived::is_running()) {
	print "Restarting VRRP...\n";
	VyattaKeepalived::restart_daemon(VyattaKeepalived::get_conf_file());
    } else {
	print "Starting VRRP...\n";
	VyattaKeepalived::start_daemon(VyattaKeepalived::get_conf_file());
    }
    exit 0;
}

#
# clear_master
#
if ($action eq "clear_master") {
    
    #
    # The kludge here to force a vrrp instance to switch from master to
    # backup is to read the keepalived config, remove the instance to be
    # cleared, signal the daemon to reread it's config.  This will cause
    # keepalived to see the old instance missing and send a priorty 0
    # advert to cause the backup to immediately take over master.  Once
    # that is done we put back the orginal config and signal the daemon
    # again.  Note: if the instance if preempt=true, then it may immediately
    # try to become master again.
    #

    if (! defined $vrrp_intf || ! defined $vrrp_group) {
	print "must include interface & group\n";
	exit 1;
    }

    my $instance = "vyatta-" . "$vrrp_intf" . "-" . "$vrrp_group";
    my $state_file = VyattaKeepalived::get_state_file($vrrp_intf, $vrrp_group);
    if (! -f $state_file) {
	print "Invalid interface/group [$vrrp_intf][$vrrp_group]\n";
	exit 1;
    }

    my ($start_time, $intf, $group, $state, $ltime) = 
	VyattaKeepalived::vrrp_state_parse($state_file);  
    if ($state ne "master") {
	print "vrrp group $vrrp_group on $vrrp_intf is already in backup\n";
	exit 1;
    }

    syslog("warning", "clear vrrp master [$instance] requested by $login");
    VyattaKeepalived::vrrp_log("vrrp clear_master $vrrp_intf $vrrp_group");

    # should add a file lock
    local($/, *FILE);  # slurp mode
    open FILE, "<", $conf_file or die "Couldn't open $conf_file\n";
    my $conf = <FILE>;
    close FILE;

    my ($new_conf, $match_instance) = vrrp_extract_instance($conf, $instance);
    if ($match_instance !~ /nopreempt/) {
	print "Warning: $instance is in preempt mode";
	print " and may retake master\n";
    }
    $match_instance = set_instance_inital_state($match_instance, "BACKUP");

    #
    # need to set the correct initial state for the remaining instances
    #
    $new_conf = set_inital_state($new_conf);

    #
    # create the temporary config file
    #
    my $tmp_conf_file = $conf_file . ".$$";
    keepalived_write_file($tmp_conf_file, $new_conf);

    my $conf_file_bak = $conf_file . ".bak";
    system("mv $conf_file $conf_file_bak");
    system("cp $tmp_conf_file $conf_file");

    VyattaKeepalived::restart_daemon($conf_file);

    print "Forcing $vrrp_intf-$group to BACKUP...\n";
    sleep(3);
    
    #
    # add modified instance back and restart
    #
    $new_conf .= "\n" . $match_instance . "\n";

    keepalived_write_file($conf_file, $new_conf);
    VyattaKeepalived::restart_daemon($conf_file);

    system("rm $conf_file_bak $tmp_conf_file");
    exit 0;
}

exit 0;

# end of file
