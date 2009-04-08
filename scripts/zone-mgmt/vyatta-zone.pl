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
# Description: Script for managing zones
# 
# **** End License ****
#

use Getopt::Long;
use POSIX;

use lib "/opt/vyatta/share/perl5";
use Vyatta::Config;
use Vyatta::Misc;

use warnings;
use strict;

# for future ease, when we add modify, these hashes will just be extended
# firewall mapping from config node to iptables command.
my %cmd_hash = ( 'name'        => '/sbin/iptables',
                 'ipv6-name'   => '/sbin/ip6tables');

# firewall mapping from config node to iptables/ip6tables table
my %table_hash = ( 'name'        => 'filter',
                   'ipv6-name'   => 'filter');

my $debug="true";
my $logger = 'sudo logger -t vyatta-zone.pl -p local0.warn --';

sub run_cmd {
    my $cmd = shift;
    
    my $error = system("$cmd");
    if ($debug eq "true") {
        my $func = (caller(1))[3];
        system("$logger [$func] [$cmd] = [$error]");
    }
    return $error;
}

sub get_all_zones {
    my $value_func = shift;
    my $config = new Vyatta::Config;
    return $config->$value_func("zone-policy zone");
}

sub get_zone_interfaces {
    my ($value_func, $zone_name) = @_;
    my $config = new Vyatta::Config;
    return $config->$value_func("zone-policy zone $zone_name interface");
}

sub get_from_zones {
    my ($value_func, $zone_name) = @_;
    my $config = new Vyatta::Config;
    return $config->$value_func("zone-policy zone $zone_name from");
}

sub get_firewall_ruleset {
    my ($value_func, $zone_name, $from_zone, $firewall_type) = @_;
    my $config = new Vyatta::Config;
    return $config->$value_func("zone-policy zone $zone_name from $from_zone
        firewall $firewall_type");
}

sub is_local_zone {
    my ($value_func, $zone_name) = @_;
    my $config = new Vyatta::Config;
    return $config->$value_func("zone-policy zone $zone_name local-zone");
}

sub rule_exists {
    my ($tree, $chain_name, $target, $interface) = @_;
    my $cmd = 
	"sudo $cmd_hash{$tree} -t $table_hash{$tree} -L " .
	"$chain_name -v 2>/dev/null | grep \" $target \" " .	
	"| grep \" $interface \" | wc -l";
    my $result = `$cmd`;
    return $result;
}

sub create_zone_chain {
    my $zone_name = shift;
    my ($cmd, $error);
    # create zone chains in filter, ip6filter tables
    foreach my $tree (keys %cmd_hash) {
     $cmd = "sudo $cmd_hash{$tree} -t $table_hash{$tree} -L zone-$zone_name >&/dev/null";
     $error = run_cmd($cmd);
     if ($error) { 
       print "$tree - $zone_name does not exists; create zone chain $zone_name\n";
       # chain does not exist, go ahead create it
       $cmd = "sudo $cmd_hash{$tree} -t $table_hash{$tree} -N zone-$zone_name";
       $error = run_cmd($cmd);
       return "Error: call to create $zone_name chain with failed [$error]" if $error;
       $cmd = "sudo $cmd_hash{$tree} -t $table_hash{$tree} -I zone-$zone_name -j DROP";
       $error = run_cmd($cmd);
       return "Error: call to add drop rule to $zone_name chain with failed [$error]" if $error;
     }
    }
    return;
}

sub delete_zone_chain {
    my $zone_name = shift;
    my ($cmd, $error);
    # delete zone chains from filter, ip6filter tables
    foreach my $tree (keys %cmd_hash) {
     print "$tree - delete zone chain $zone_name\n";
     $cmd = "sudo $cmd_hash{$tree} -t $table_hash{$tree} -F zone-$zone_name";
     $error = run_cmd($cmd);
     return "Error: call to flush all rules in $zone_name chain with failed [$error]" if $error;
     $cmd = "sudo $cmd_hash{$tree} -t $table_hash{$tree} -X zone-$zone_name";
     $error = run_cmd($cmd);
     return "Error: call to delete $zone_name chain with failed [$error]" if $error;
    }
    return;
}

sub count_iptables_rules {
    my ($type, $chain) = @_;
    my @lines = `sudo $cmd_hash{$type} -t $table_hash{$type} -L $chain -n --line`;
    my $cnt = 0;
    foreach my $line (@lines) {
      $cnt++ if $line =~ /^\d/;
    }
    return $cnt;
}

sub add_fromzone_intf_ruleset {
    my ($zone_name, $from_zone, $interface, $ruleset_type, $ruleset) = @_;
    # check if ruleset type has a value
    my ($cmd, $error);
    my $ruleset_name;
    if (defined $ruleset) { # called from node.def
        $ruleset_name=$ruleset;
    } else { # called from do_firewall_interface_zone()
        $ruleset_name=get_firewall_ruleset("returnValue", $zone_name, $from_zone, $ruleset_type);
    }
    if (defined $ruleset_name) {
     print "$ruleset_type - insert rules for jumping to $ruleset_name for $interface in zone-$zone_name chain\n";
     # get number of rules in ruleset_name
     my $rule_cnt = count_iptables_rules($ruleset_type, "zone-$zone_name");
     # append rules before last drop all rule
     my $insert_at_rule_num=1;
     if ( $rule_cnt > 1 ) {
        $insert_at_rule_num=$rule_cnt;
     }
     my $result = rule_exists ($ruleset_type, "zone-$zone_name", $ruleset_name, $interface);
     if ($result < 1) {
      $cmd = "sudo $cmd_hash{$ruleset_type} -t $table_hash{$ruleset_type} " . 
	"-I zone-$zone_name $insert_at_rule_num -i $interface -j $ruleset_name";
      $error = run_cmd($cmd);
      return "Error: call to insert rule for incoming interface $interface 
into zone-chain zone-$zone_name with target $ruleset_name failed [$error]" if $error;
      # insert the RETURN rule next
      $insert_at_rule_num++;
      $cmd = "sudo $cmd_hash{$ruleset_type} -t $table_hash{$ruleset_type} " .
	"-I zone-$zone_name $insert_at_rule_num -i $interface -j RETURN";
      $error = run_cmd($cmd);
      return "Error: call to insert rule for incoming interface $interface
into zone chain zone-$zone_name with target RETURN failed [$error]" if $error;
     }
    }
    return;
}

sub delete_fromzone_intf_ruleset {
    my ($zone_name, $from_zone, $interface, $ruleset_type, $ruleset) = @_;
    # check if ruleset type has a value
    my ($cmd, $error);
    my $ruleset_name;
    if (defined $ruleset) { # called from node.def
	$ruleset_name=$ruleset;
    } else { # called from undo_firewall_interface_zone()
	$ruleset_name=get_firewall_ruleset("returnOrigValue", $zone_name, $from_zone, $ruleset_type);
    }
    if (defined $ruleset_name) {
     print "$ruleset_type - delete rules for jumping to $ruleset_name for $interface in zone-$zone_name chain\n";
     $cmd = "sudo $cmd_hash{$ruleset_type} -t $table_hash{$ruleset_type} " .
	"-D zone-$zone_name -i $interface -j $ruleset_name";
     $error = run_cmd($cmd);
     return "Error: call to delete rule for incoming interface $interface 
in zone chain zone-$zone_name with target $ruleset_name failed [$error]" if $error;
     $cmd = "sudo $cmd_hash{$ruleset_type} -t $table_hash{$ruleset_type} " .
	"-D zone-$zone_name -i $interface -j RETURN";
     $error = run_cmd($cmd);
     return "Error: call to delete rule for incoming interface $interface into 
zone chain zone-$zone_name with target RETURN for $zone_name failed [$error]" if $error;
    } 
    return;
}

sub do_firewall_interface_zone {
    my ($zone_name, $interface) = @_;
    my ($cmd, $error);
    # add rule to allow same zone to same zone traffic
    foreach my $tree (keys %cmd_hash) {
     print "$tree - add interface $interface to zone $zone_name\n";
     my $result = rule_exists ($tree, "zone-$zone_name", "RETURN", $interface);
     if ($result < 1) {
      $cmd = "sudo $cmd_hash{$tree} -t $table_hash{$tree} -I zone-$zone_name " .
	"-i $interface -j RETURN";
      $error = run_cmd($cmd);
      return "Error: call to add $interface to its zone-chain zone-$zone_name 
failed [$error]" if $error;
     }
     # need to do this as an append before VYATTA_POST_FW_HOOK
     my $rule_cnt = count_iptables_rules($tree, "FORWARD");
     my $insert_at_rule_num=1;
     if ( $rule_cnt > 1 ) {
        $insert_at_rule_num=$rule_cnt;
     }
     $result = rule_exists ($tree, "FORWARD", "zone-$zone_name", $interface);
     if ($result < 1) {
      $cmd = "sudo $cmd_hash{$tree} -t $table_hash{$tree} -I FORWARD $insert_at_rule_num " . 
	"-o $interface -j zone-$zone_name";
      $error = run_cmd($cmd);
      return "Error: call to add jump rule for outgoing interface $interface to 
its zone-$zone_name chain failed [$error]" if $error;
     }
    }
    
    # get all zones in which this zone is being used as a from zone
    # then in chains for those zones, add rules for this incoming interface
    my @all_zones = get_all_zones("listNodes");
    foreach my $zone (@all_zones) {
      if (!($zone eq $zone_name)) {
        my @from_zones = get_from_zones("listNodes", $zone);
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
    return;
}

sub undo_firewall_interface_zone {
    my ($zone_name, $interface) = @_;
    my ($cmd, $error);

    # delete rule to allow same zone to same zone traffic
    foreach my $tree (keys %cmd_hash) {
     print "$tree - delete interface $interface from zone $zone_name\n";
     $cmd = "sudo $cmd_hash{$tree} -t $table_hash{$tree} -D FORWARD " .
	"-o $interface -j zone-$zone_name";
     $error = run_cmd($cmd);
     return "Error: call to delete jump rule for outgoing interface $interface 
to zone-$zone_name chain failed [$error]" if $error;

     $cmd = "sudo $cmd_hash{$tree} -t $table_hash{$tree} -D zone-$zone_name " .
	"-i $interface -j RETURN";
     $error = run_cmd($cmd);
     return "Error: call to delete interface $interface from zone-chain 
zone-$zone_name with failed [$error]" if $error;
    }

    # delete rules for this interface where this zone is being used as a from zone
    my @all_zones = get_all_zones("listOrigNodes");
    foreach my $zone (@all_zones) {
      if (!($zone eq $zone_name)) {
        my @from_zones = get_from_zones("listOrigNodes", $zone);
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
    return;
}

sub add_zone {
    my $zone_name = shift;
    print "perform add zone actions for $zone_name\n";
    # perform firewall related actions for this zone
    my $error = create_zone_chain ($zone_name);
    return ($error, ) if $error;
    return;
}

sub delete_zone {
    my $zone_name = shift;
    print "perform delete zone actions for $zone_name\n";
    # undo firewall related actions for this zone
    my $error = delete_zone_chain ($zone_name);
    return ($error, ) if $error;
    return;    
}

sub add_zone_interface {
    my ($zone_name, $interface) = @_;
    print "perform add interface $interface to zone $zone_name\n";
    return("Error: undefined interface", ) if ! defined $interface;
    my $error;
    # do firewall related stuff
    $error = do_firewall_interface_zone ($zone_name, $interface);
    return ($error, ) if $error;
    return;
}

sub delete_zone_interface {
    my ($zone_name, $interface) = @_;
    print "perform delete interface $interface from zone $zone_name\n";
    return("Error: undefined interface", ) if ! defined $interface;
    # undo firewall related stuff
    my $error = undo_firewall_interface_zone ($zone_name, $interface);
    return ($error, ) if $error;
    return;
}

sub add_fromzone_fw {
    my ($zone, $from_zone, $ruleset_type, $ruleset_name) = @_;
    my $error;
    # get all interfaces in from_zone
    # call sub add_fromzone_intf_ruleset for each interface in from zone with these parameters
    # $zone_name, $from_zone, $interface, $ruleset_type
    print "apply $ruleset_type ruleset to filter traffic from zone $from_zone to $zone\n";
    my @from_zone_interfaces = get_zone_interfaces("returnValues", $from_zone);
    foreach my $intf (@from_zone_interfaces) {
      $error = add_fromzone_intf_ruleset($zone, $from_zone, $intf, $ruleset_type, $ruleset_name);
      return "Error: $error" if $error;
    }
    return;
}

sub delete_fromzone_fw {
    my ($zone, $from_zone, $ruleset_type, $ruleset_name) = @_;
    my $error;
    # get all interfaces in from_zone
    # call sub delete_fromzone_intf_ruleset for each interface in from zone with these parameters
    # $zone_name, $from_zone, $interface, $ruleset_type
    print "delete $ruleset_type ruleset to filter traffic from zone $from_zone to $zone\n";
    my @from_zone_interfaces = get_zone_interfaces("returnOrigValues", $from_zone);
    foreach my $intf (@from_zone_interfaces) {
      $error = delete_fromzone_intf_ruleset($zone, $from_zone, $intf, $ruleset_type, $ruleset_name);
      return "Error: $error" if $error;
    }
    return;
}

sub validity_checks {
    my @all_zones = get_all_zones("listNodes");
    my @all_interfaces = ();
    my $num_local_zones = 0;
    foreach my $zone (@all_zones) {
      # get all from zones, see if they exist in config, if not => error out
      print "check all from zones under $zone have zone definitions for them\n";
      my @from_zones = get_from_zones("listNodes", $zone);
      foreach my $from_zone (@from_zones) {
        if (scalar(grep(/^$from_zone$/, @all_zones)) == 0) {
          return ("from zone $from_zone under zone $zone is either not defined or deleted from config", );
        }
      }
      print "check $zone has either interfaces defined or is local-zone\n";
      my @zone_intfs = get_zone_interfaces("returnValues", $zone);
      if (scalar(@zone_intfs) == 0) {
        # no interfaces defined for this zone
        if (!defined(is_local_zone("exists", $zone))) {
          return("Zone $zone has no interfaces defined and it's not a local-zone", );
        }
        $num_local_zones++;
        # make sure only one zone is a local-zone
        if ($num_local_zones > 1) {
          return ("Only one zone can be defined as a local-zone", );
        }
      } else {
        # zone has interfaces defined for it, make sure it is not set as a local-zone
        if (defined(is_local_zone("exists", $zone))) {
          return("Zone $zone has interfaces defined. It cannot be a local-zone", );
        }
        # check for each interface if it is in @all_interfaces, if not push it to @all_interfaces
        foreach my $interface (@zone_intfs) {
          if (scalar(grep(/^$interface$/, @all_interfaces)) > 0) {
            return ("interface $interface defined under two zones. @all_interfaces", );
          } else {
            push(@all_interfaces, $interface);
          }
        }
      }
    }
    return;
}

#
# main
#

my ($action, $zone_name, $interface, $from_zone, $ruleset_type, $ruleset_name);

GetOptions("action=s"         => \$action,
           "zone-name=s"      => \$zone_name,
	   "interface=s"      => \$interface,
	   "from-zone=s"      => \$from_zone,
           "ruleset-type=s"   => \$ruleset_type,
	   "ruleset-name=s"   => \$ruleset_name,
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

($error, $warning) = add_fromzone_fw($zone_name, $from_zone, $ruleset_type, $ruleset_name)
                        if $action eq 'add-fromzone-fw';

($error, $warning) = delete_fromzone_fw($zone_name, $from_zone, $ruleset_type, $ruleset_name)
                        if $action eq 'delete-fromzone-fw';

($error, $warning) = validity_checks() if $action eq 'validity-checks';

if (defined $warning) {
    print "$warning\n";
}

if (defined $error) {
    print "$error\n";
    exit 1;
}

exit 0;

# end of file
