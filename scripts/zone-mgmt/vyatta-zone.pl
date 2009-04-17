#!/usr/bin/perl
#
# Module: vyatta-zone.pl
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
# Portions created by Vyatta are Copyright (C) 2009 Vyatta, Inc.
# All Rights Reserved.
# 
# Author: Mohit Mehta
# Date: April 2009
# Description: Script for Zone Based Firewall
# 
# **** End License ****
#

use Getopt::Long;
use POSIX;

use lib "/opt/vyatta/share/perl5";
use Vyatta::Zone;

use warnings;
use strict;

# for future ease, when we add modify, these hashes will just be extended
# firewall mapping from config node to iptables command.
my %cmd_hash = ( 'name'        => '/sbin/iptables',
                 'ipv6-name'   => '/sbin/ip6tables');

# firewall mapping from config node to iptables/ip6tables table
my %table_hash = ( 'name'        => 'filter',
                   'ipv6-name'   => 'filter');

# mapping from vyatta 'default-policy' to iptables jump target
my %policy_hash = ( 'drop'    => 'DROP',
                    'reject'  => 'REJECT' );

sub setup_default_policy {
    my ($zone_name, $default_policy, $localoutchain) = @_;
    my ($cmd, $error);
    my $zone_chain=Vyatta::Zone::get_zone_chain("exists",
                        $zone_name, $localoutchain);

    # add default policy for zone chains in filter, ip6filter tables
    foreach my $tree (keys %cmd_hash) {

      # set default policy for zone chain
      $cmd = "sudo $cmd_hash{$tree} -t $table_hash{$tree} -A " .
                "$zone_chain -j $policy_hash{$default_policy}";
      $error =  Vyatta::Zone::run_cmd("$cmd");
      return "Error: set default policy $zone_chain failed [$error]" if $error;

      my $rule_cnt = Vyatta::Zone::count_iptables_rules($cmd_hash{$tree},
                                $table_hash{$tree}, $zone_chain);

      # if there's a drop|reject rule at rule_cnt - 1 then remove that
      # in zone chain a drop|reject target can only be for default policy
      if ($rule_cnt > 1) {
        my $penultimate_rule_num=$rule_cnt-1;
        $cmd = "sudo $cmd_hash{$tree} -t $table_hash{$tree} " .
                "-L $zone_chain $penultimate_rule_num -v | awk {'print \$3'}";
        my $target=`$cmd`;
        chomp $target;
        if (defined $target && ($target eq 'REJECT' || $target eq 'DROP')) {
          $cmd = "sudo $cmd_hash{$tree} -t $table_hash{$tree} -D " .
                 "$zone_chain $penultimate_rule_num";
          $error =  Vyatta::Zone::run_cmd("$cmd");
          return "Error: delete rule $penultimate_rule_num with $target
in $zone_name chain failed [$error]" if $error;
        }
      }
    }
    return;
}

sub create_zone_chain {
    my ($zone_name, $localoutchain) = @_;
    my ($cmd, $error);
    my $zone_chain=Vyatta::Zone::get_zone_chain("exists", 
			$zone_name, $localoutchain);
    
    # create zone chains in filter, ip6filter tables
    foreach my $tree (keys %cmd_hash) {
     $cmd = "sudo $cmd_hash{$tree} -t $table_hash{$tree} " . 
		"-L $zone_chain >&/dev/null";
     $error = Vyatta::Zone::run_cmd($cmd);
     if ($error) { 
       # chain does not exist, go ahead create it
       $cmd = "sudo $cmd_hash{$tree} -t $table_hash{$tree} -N $zone_chain";
       $error = Vyatta::Zone::run_cmd($cmd);
       return "Error: create $zone_name chain with failed [$error]" if $error;
     }
    }
    
    return;
}

sub delete_zone_chain {
    my ($zone_name, $localoutchain) = @_;
    my ($cmd, $error);
    my $zone_chain=Vyatta::Zone::get_zone_chain("existsOrig", 
			$zone_name, $localoutchain);
    # delete zone chains from filter, ip6filter tables
    foreach my $tree (keys %cmd_hash) {
     # flush all rules from zone chain
     $cmd = "sudo $cmd_hash{$tree} -t $table_hash{$tree} -F $zone_chain";
     $error = Vyatta::Zone::run_cmd($cmd);
     return "Error: flush all rules in $zone_name chain failed [$error]" if $error;

     # delete zone chain
     $cmd = "sudo $cmd_hash{$tree} -t $table_hash{$tree} -X $zone_chain";
     $error = Vyatta::Zone::run_cmd($cmd);
     return "Error: delete $zone_name chain failed [$error]" if $error;
    }
    return;
}

sub insert_from_rule {
    my ($zone_name, $from_zone, $interface, $ruleset_type, $ruleset,
        $direction, $zone_chain) = @_;
    my ($cmd, $error);
    my $ruleset_name;

    if (defined $ruleset) { # called from node.def
        $ruleset_name=$ruleset;
    } else { # called from do_firewall_interface_zone()
        $ruleset_name=Vyatta::Zone::get_firewall_ruleset("returnValue",
                        $zone_name, $from_zone, $ruleset_type);
    }

    if (defined $ruleset_name) {
     # get number of rules in ruleset_name
     my $rule_cnt = Vyatta::Zone::count_iptables_rules($cmd_hash{$ruleset_type},
                 $table_hash{$ruleset_type}, "$zone_chain");
     # append rules before last drop all rule
     my $insert_at_rule_num=1;
     if ( $rule_cnt > 1 ) {
        $insert_at_rule_num=$rule_cnt;
     }
     my $result = Vyatta::Zone::rule_exists ($cmd_hash{$ruleset_type},
	$table_hash{$ruleset_type}, "$zone_chain", $ruleset_name, $interface);
     if ($result < 1) {
      # append rule before drop rule to jump to ruleset for in\out interface
      $cmd = "sudo $cmd_hash{$ruleset_type} -t $table_hash{$ruleset_type} " . 
"-I $zone_chain $insert_at_rule_num $direction $interface -j $ruleset_name";
      $error = Vyatta::Zone::run_cmd($cmd);
      return "Error: insert rule for $direction $interface into zone-chain 
$zone_chain with target $ruleset_name failed [$error]" if $error;

      # insert the RETURN rule next
      $insert_at_rule_num++;
      $cmd = "sudo $cmd_hash{$ruleset_type} -t $table_hash{$ruleset_type} " .
        "-I $zone_chain $insert_at_rule_num $direction $interface -j RETURN";
      $error = Vyatta::Zone::run_cmd($cmd);
      return "Error: insert rule for $direction $interface into zone chain 
$zone_chain with target RETURN failed [$error]" if $error;
     }
    }

    return;
}


sub add_fromzone_intf_ruleset {
    my ($zone_name, $from_zone, $interface, $ruleset_type, $ruleset) = @_;
    my $zone_chain=Vyatta::Zone::get_zone_chain("exists", $zone_name);
    my $error = insert_from_rule ($zone_name, $from_zone, $interface,
                $ruleset_type, $ruleset, '-i', $zone_chain);
    return ($error, ) if $error;
    return;
}

sub add_fromlocalzone_ruleset {
    my ($zone_name, $from_zone, $interface, $ruleset_type, $ruleset) = @_;
    my $zone_chain=Vyatta::Zone::get_zone_chain("exists", $from_zone, "localout");

    my $error = insert_from_rule ($zone_name, $from_zone, $interface,
                $ruleset_type, $ruleset, '-o', $zone_chain);
    return ($error, ) if $error;

     # if jump to localzoneout chain not inserted, then insert rule
     my $rule_cnt = Vyatta::Zone::count_iptables_rules($cmd_hash{$ruleset_type},
                $table_hash{$ruleset_type}, "OUTPUT");
     my $insert_at_rule_num=1;
     if ( $rule_cnt > 1 ) {
        $insert_at_rule_num=$rule_cnt;
     }
     my $result = Vyatta::Zone::rule_exists ($cmd_hash{$ruleset_type},
        $table_hash{$ruleset_type}, "OUTPUT", $zone_chain);
     if ($result < 1) {
      my $cmd = "sudo $cmd_hash{$ruleset_type} -t $table_hash{$ruleset_type} " . 
	"-I OUTPUT $insert_at_rule_num -j $zone_chain";
      $error = Vyatta::Zone::run_cmd($cmd);
      return "Error: call to add jump rule for local zone out
$zone_chain chain failed [$error]" if $error;
     }

    return;
}

sub delete_from_rule {

    my ($zone_name, $from_zone, $interface, $ruleset_type, $ruleset, 
	$direction, $zone_chain) = @_;
    my ($cmd, $error);
    my $ruleset_name;

    if (defined $ruleset) { # called from node.def
        $ruleset_name=$ruleset;
    } else { # called from undo_firewall_interface_zone()
        $ruleset_name=Vyatta::Zone::get_firewall_ruleset("returnOrigValue", 
		$zone_name, $from_zone, $ruleset_type);
    }

    if (defined $ruleset_name) {
     # delete rule to jump to ruleset for in|out interface in zone chain
     $cmd = "sudo $cmd_hash{$ruleset_type} -t $table_hash{$ruleset_type} " .
        "-D $zone_chain $direction $interface -j $ruleset_name";
     $error = Vyatta::Zone::run_cmd($cmd);
     return "Error: call to delete rule for $direction $interface
in zone chain $zone_chain with target $ruleset_name failed [$error]" if $error;
     
     # delete RETURN rule for same interface
     $cmd = "sudo $cmd_hash{$ruleset_type} -t $table_hash{$ruleset_type} " .
        "-D $zone_chain $direction $interface -j RETURN";
     $error = Vyatta::Zone::run_cmd($cmd);
     return "Error: call to delete rule for $direction $interface into zone 
chain $zone_chain with target RETURN for $zone_name failed [$error]" if $error;
    }

    return;
}

sub delete_fromzone_intf_ruleset {
    my ($zone_name, $from_zone, $interface, $ruleset_type, $ruleset) = @_;
    my $zone_chain=Vyatta::Zone::get_zone_chain("existsOrig", $zone_name);
    my $error = delete_from_rule ($zone_name, $from_zone, $interface, 
		$ruleset_type, $ruleset, '-i', $zone_chain);
    return ($error, ) if $error;
    return;
}

sub delete_fromlocalzone_ruleset {
    my ($zone_name, $from_zone, $interface, $ruleset_type, $ruleset) = @_;
    my $zone_chain=Vyatta::Zone::get_zone_chain("existsOrig", 
			$from_zone, "localout");

    my ($cmd, $error);
    $error = delete_from_rule ($zone_name, $from_zone, $interface, 
		$ruleset_type, $ruleset, '-o', $zone_chain);
    return ($error, ) if $error;

    # if only drop rule in $zone_chain, then delete jump from OUTPUT chain
    my $rule_cnt = Vyatta::Zone::count_iptables_rules($cmd_hash{$ruleset_type}, 
	$table_hash{$ruleset_type}, $zone_chain);
    if ($rule_cnt < 2) {
      $cmd = "sudo $cmd_hash{$ruleset_type} -t $table_hash{$ruleset_type} " . 
	"-D OUTPUT -j $zone_chain";
      $error = Vyatta::Zone::run_cmd($cmd);
      return "Error: call to delete jump rule for local zone out
$zone_chain chain failed [$error]" if $error;
     }
    return;
}

sub do_firewall_interface_zone {
    my ($zone_name, $interface) = @_;
    my $zone_chain=Vyatta::Zone::get_zone_chain("exists", $zone_name);
    my ($cmd, $error);
    foreach my $tree (keys %cmd_hash) {

     my $result = Vyatta::Zone::rule_exists ($cmd_hash{$tree}, 
	$table_hash{$tree}, "$zone_chain", "RETURN", $interface);
     if ($result < 1) {
      # add rule to allow same zone to same zone traffic
      $cmd = "sudo $cmd_hash{$tree} -t $table_hash{$tree} -I $zone_chain " .
	"-i $interface -j RETURN";
      $error = Vyatta::Zone::run_cmd($cmd);
      return "Error: call to add $interface to its zone-chain $zone_chain 
failed [$error]" if $error;
     }

     # need to do this as an append before VYATTA_POST_FW_HOOK
     my $rule_cnt = Vyatta::Zone::count_iptables_rules($cmd_hash{$tree}, 
		$table_hash{$tree}, "FORWARD");
     my $insert_at_rule_num=1;
     if ( $rule_cnt > 1 ) {
        $insert_at_rule_num=$rule_cnt;
     }
     $result = Vyatta::Zone::rule_exists ($cmd_hash{$tree}, $table_hash{$tree}, 
		"FORWARD", "$zone_chain", $interface);
     if ($result < 1) {
      $cmd = "sudo $cmd_hash{$tree} -t $table_hash{$tree} -I FORWARD " . 
	"$insert_at_rule_num -o $interface -j $zone_chain";
      $error = Vyatta::Zone::run_cmd($cmd);
      return "Error: call to add jump rule for outgoing interface $interface 
to its $zone_chain chain failed [$error]" if $error;
     }
    }
    
    # get all zones in which this zone is being used as a from zone
    # then in chains for those zones, add rules for this incoming interface
    my @all_zones = Vyatta::Zone::get_all_zones("listNodes");
    foreach my $zone (@all_zones) {
      if (!($zone eq $zone_name)) {
        my @from_zones = Vyatta::Zone::get_from_zones("listNodes", $zone);
	if (scalar(grep(/^$zone_name$/, @from_zones)) > 0) {
	  foreach my $tree (keys %cmd_hash) {
            # call function to append rules to $zone's chain
	    $error = add_fromzone_intf_ruleset($zone, $zone_name, 
			$interface, $tree);
	    return "Error: $error" if $error;
	  }
	}
      }
    }

    # if this zone has a local from zone, add interface to local zone out chain
    my @my_from_zones = Vyatta::Zone::get_from_zones("listNodes", $zone_name);
    foreach my $fromzone (@my_from_zones) {
      if (defined(Vyatta::Zone::is_local_zone("exists", $fromzone))) {
        foreach my $tree (keys %cmd_hash) {
          $error = add_fromlocalzone_ruleset($zone_name, $fromzone,
                        $interface, $tree);
          return "Error: $error" if $error;
        }
      }
    }

    return;
}

sub undo_firewall_interface_zone {
    my ($zone_name, $interface) = @_;
    my ($cmd, $error);
    my $zone_chain=Vyatta::Zone::get_zone_chain("existsOrig", $zone_name);

    foreach my $tree (keys %cmd_hash) {

     # delete rule to allow same zone to same zone traffic
     $cmd = "sudo $cmd_hash{$tree} -t $table_hash{$tree} -D FORWARD " .
	"-o $interface -j $zone_chain";
     $error = Vyatta::Zone::run_cmd($cmd);
     return "Error: call to delete jump rule for outgoing interface $interface 
to $zone_chain chain failed [$error]" if $error;

     # delete ruleset jump for this in interface
     $cmd = "sudo $cmd_hash{$tree} -t $table_hash{$tree} -D $zone_chain " .
	"-i $interface -j RETURN";
     $error = Vyatta::Zone::run_cmd($cmd);
     return "Error: call to delete interface $interface from zone-chain 
$zone_chain with failed [$error]" if $error;
    }

    # delete rules for this intf where this zone is being used as a from zone
    my @all_zones = Vyatta::Zone::get_all_zones("listOrigNodes");
    foreach my $zone (@all_zones) {
      if (!($zone eq $zone_name)) {
        my @from_zones = Vyatta::Zone::get_from_zones("listOrigNodes", $zone);
        if (scalar(grep(/^$zone_name$/, @from_zones)) > 0) {
          foreach my $tree (keys %cmd_hash) {
            # call function to delete rules from $zone's chain
            $error = delete_fromzone_intf_ruleset($zone, $zone_name, 
			$interface, $tree);
            return "Error: $error" if $error;
          }
        }
      }
    }

    # if you have local from zone, delete interface to local zone out chain
    my @my_from_zones = Vyatta::Zone::get_from_zones("listOrigNodes", $zone_name);
    foreach my $fromzone (@my_from_zones) {
      if (defined(Vyatta::Zone::is_local_zone("existsOrig", $fromzone))) {
        foreach my $tree (keys %cmd_hash) {
          $error = delete_fromlocalzone_ruleset($zone_name, $fromzone,
                        $interface, $tree);
          return "Error: $error" if $error;
        }
      }
    }

    return;
}

sub do_firewall_localzone {
    my ($zone_name) = @_;
    my ($cmd, $error);
    my $zone_chain=Vyatta::Zone::get_zone_chain("exists", $zone_name);
    foreach my $tree (keys %cmd_hash) {

     my $rule_cnt = Vyatta::Zone::count_iptables_rules($cmd_hash{$tree}, 
		$table_hash{$tree}, "INPUT");
     my $insert_at_rule_num=1;
     if ( $rule_cnt > 1 ) {
        $insert_at_rule_num=$rule_cnt;
     }
     my $result = Vyatta::Zone::rule_exists ($cmd_hash{$tree}, 
		$table_hash{$tree}, "INPUT", $zone_chain);

     if ($result < 1) {
      # insert rule to filter local traffic from interface per ruleset
      $cmd = "sudo $cmd_hash{$tree} -t $table_hash{$tree} -I INPUT " .
        "$insert_at_rule_num -j $zone_chain";
      $error = Vyatta::Zone::run_cmd($cmd);
      return "Error: call to add jump rule for local zone
$zone_chain chain failed [$error]" if $error;
     }
    }

    # get all zones in which local zone is being used as a from zone
    # filter traffic from local zone to those zones
    my @all_zones = Vyatta::Zone::get_all_zones("listNodes");
    foreach my $zone (@all_zones) {
      if (!($zone eq $zone_name)) {
        my @from_zones = Vyatta::Zone::get_from_zones("listNodes", $zone);
        if (scalar(grep(/^$zone_name$/, @from_zones)) > 0) {
          foreach my $tree (keys %cmd_hash) {
            my @zone_interfaces = 
		Vyatta::Zone::get_zone_interfaces("returnValues", $zone);
            foreach my $intf (@zone_interfaces) {
              $error = add_fromlocalzone_ruleset($zone, $zone_name,
                        $intf, $tree);
              return "Error: $error" if $error;
            }
          }
        }
      }
    }
    return;
}

sub undo_firewall_localzone {
    my ($zone_name) = @_;
    my ($cmd, $error);
    my $zone_chain=Vyatta::Zone::get_zone_chain("existsOrig", $zone_name);

    foreach my $tree (keys %cmd_hash) {
     
     # delete rule to filter traffic destined for system
     $cmd = "sudo $cmd_hash{$tree} -t $table_hash{$tree} -D INPUT " .
        "-j $zone_chain";
     $error = Vyatta::Zone::run_cmd($cmd);
     return "Error: call to delete local zone
$zone_chain chain failed [$error]" if $error;
    }

    # get all zones in which local zone is being used as a from zone
    # remove filter for traffic from local zone to those zones
    my @all_zones = Vyatta::Zone::get_all_zones("listOrigNodes");
    foreach my $zone (@all_zones) {
      if (!($zone eq $zone_name)) {
        my @from_zones = Vyatta::Zone::get_from_zones("listOrigNodes", $zone);
        if (scalar(grep(/^$zone_name$/, @from_zones)) > 0) {
          foreach my $tree (keys %cmd_hash) {
	    my @zone_interfaces = 
		Vyatta::Zone::get_zone_interfaces("returnOrigValues", $zone);
            foreach my $intf (@zone_interfaces) {
              $error = delete_fromlocalzone_ruleset($zone, $zone_name,
                        $intf, $tree);
              return "Error: $error" if $error;
            }
          }
        }
      }
    }
    return;
}

sub add_zone {
    my $zone_name = shift;
    # perform firewall related actions for this zone
    my $error = create_zone_chain ($zone_name);
    return ($error, ) if $error;
    if (defined(Vyatta::Zone::is_local_zone("exists", $zone_name))) {
      # make local out chain as well
      $error = create_zone_chain ($zone_name, "localout");
      return ($error, ) if $error;
    }
    # set default policy
    my $default_policy = Vyatta::Zone::get_zone_default_policy("returnValue",
                                $zone_name);
    $error = set_default_policy($zone_name, $default_policy);
    return $error if $error;
    return;
}

sub delete_zone {
    my $zone_name = shift;
    # undo firewall related actions for this zone
    my $error = delete_zone_chain ($zone_name);
    return ($error, ) if $error;
    if (defined(Vyatta::Zone::is_local_zone("existsOrig", $zone_name))) {
      # delete local out chain as well
      $error = delete_zone_chain ($zone_name, "localout");
      return ($error, ) if $error;
    }
    return;    
}

sub add_localzone {
    my ($zone_name) = @_;
    my $error;
    # do firewall related stuff
    $error = do_firewall_localzone ($zone_name);
    return ($error, ) if $error;
    return;
}

sub delete_localzone {
    my ($zone_name) = @_;
    my $error;
    # undo firewall related stuff
    $error = undo_firewall_localzone ($zone_name);
    return ($error, ) if $error;
    return;
}

sub add_zone_interface {
    my ($zone_name, $interface) = @_;
    return("Error: undefined interface", ) if ! defined $interface;
    my $error;
    # do firewall related stuff
    $error = do_firewall_interface_zone ($zone_name, $interface);
    return ($error, ) if $error;
    return;
}

sub delete_zone_interface {
    my ($zone_name, $interface) = @_;
    return("Error: undefined interface", ) if ! defined $interface;
    # undo firewall related stuff
    my $error = undo_firewall_interface_zone ($zone_name, $interface);
    return ($error, ) if $error;
    return;
}

sub add_fromzone_fw {
    my ($zone, $from_zone, $ruleset_type, $ruleset_name) = @_;
    my $error;

    # for all interfaces in from zone apply ruleset to filter traffic
    # from this zone to specified zone (i.e. $zone)
    my @from_zone_interfaces = 
	Vyatta::Zone::get_zone_interfaces("returnValues", $from_zone);
    if (scalar(@from_zone_interfaces) > 0) {
      foreach my $intf (@from_zone_interfaces) {
        $error = add_fromzone_intf_ruleset($zone, $from_zone, $intf, 
			$ruleset_type, $ruleset_name);
        return "Error: $error" if $error;
      }
    } else {
      if (defined(Vyatta::Zone::is_local_zone("exists", $from_zone))) {
        # local from zone
        my @zone_interfaces = 
		Vyatta::Zone::get_zone_interfaces("returnValues", $zone);
        foreach my $intf (@zone_interfaces) {
          $error = add_fromlocalzone_ruleset($zone, $from_zone, $intf, 
			$ruleset_type, $ruleset_name);
          return "Error: $error" if $error;        
        }
      }
    }

    return;
}

sub delete_fromzone_fw {
    my ($zone, $from_zone, $ruleset_type, $ruleset_name) = @_;
    my $error;

    # for all interfaces in from zone remove ruleset to filter traffic
    # from this zone to specified zone (i.e. $zone)
    my @from_zone_interfaces = 
	Vyatta::Zone::get_zone_interfaces("returnOrigValues", $from_zone);
    if (scalar(@from_zone_interfaces) > 0) {
      foreach my $intf (@from_zone_interfaces) {
        $error = delete_fromzone_intf_ruleset($zone, $from_zone, $intf, 
			$ruleset_type, $ruleset_name);
        return "Error: $error" if $error;
      }
    } else {
      if (defined(Vyatta::Zone::is_local_zone("existsOrig", $from_zone))) {
        # local from zone
        my @zone_interfaces = 
		Vyatta::Zone::get_zone_interfaces("returnOrigValues", $zone);
        foreach my $intf (@zone_interfaces) {
          $error = delete_fromlocalzone_ruleset($zone, $from_zone, $intf, 
			$ruleset_type, $ruleset_name);
          return "Error: $error" if $error;
        }
      }
    }
    return;
}

sub set_default_policy {
    my ($zone, $default_policy) = @_;
    # setup default policy for zone
    my $error = setup_default_policy ($zone, $default_policy);
    return ($error, ) if $error;
    if (defined(Vyatta::Zone::is_local_zone("exists", $zone))) {
      # set default policy for local out chain as well
      $error = setup_default_policy ($zone, $default_policy, "localout");
      return ($error, ) if $error;
    }
    return;
}

#
# main
#

my ($action, $zone_name, $interface, $from_zone, $ruleset_type, $ruleset_name,
	$default_policy);

GetOptions("action=s"         => \$action,
           "zone-name=s"      => \$zone_name,
	   "interface=s"      => \$interface,
	   "from-zone=s"      => \$from_zone,
           "ruleset-type=s"   => \$ruleset_type,
	   "ruleset-name=s"   => \$ruleset_name,
           "default-policy=s" => \$default_policy,
);

die "undefined action" if ! defined $action;
die "undefined zone" if ! defined $zone_name;

my ($error, $warning);

($error, $warning) = add_zone($zone_name) if $action eq 'add-zone';

($error, $warning) = delete_zone($zone_name) if $action eq 'delete-zone';

($error, $warning) = add_zone_interface($zone_name, $interface) 
			if $action eq 'add-zone-interface';

($error, $warning) = delete_zone_interface($zone_name, $interface) 
			if $action eq 'delete-zone-interface';

($error, $warning) = add_fromzone_fw($zone_name, $from_zone, $ruleset_type, 
			$ruleset_name) if $action eq 'add-fromzone-fw';

($error, $warning) = delete_fromzone_fw($zone_name, $from_zone, $ruleset_type, 
			$ruleset_name) if $action eq 'delete-fromzone-fw';

($error, $warning) = Vyatta::Zone::validity_checks() 
			if $action eq 'validity-checks';

($error, $warning) = add_localzone($zone_name)
                        if $action eq 'add-localzone';

($error, $warning) = delete_localzone($zone_name)
                        if $action eq 'delete-localzone';

($error, $warning) = set_default_policy($zone_name, $default_policy)
                        if $action eq 'set-default-policy';

if (defined $warning) {
    print "$warning\n";
}

if (defined $error) {
    print "$error\n";
    exit 1;
}

exit 0;

# end of file
