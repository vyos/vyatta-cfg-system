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
# Portions created by Vyatta are Copyright (C) 2007-2009 Vyatta, Inc.
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
use Vyatta::Interface;
use Vyatta::ConntrackSync;
use Vyatta::Misc;
use Getopt::Long;

use strict;
use warnings;

my ( $action, $vrrp_intf, $vrrp_group, $vrrp_vip, $ctsync );
my ( $conf_file, $changes_file );
my %HoA_sync_groups;
my $ctsync_script = "/opt/vyatta/sbin/vyatta-vrrp-conntracksync.sh";

sub validate_source_addr {
  my ( $ifname, $source_addr ) = @_;

  if ( defined $source_addr ) {
    unless (is_local_address ( $source_addr )) {
      vrrp_log("hello-source not local");
      return "hello-source-address [$source_addr] must be "
        . "configured on the interface\n";
    }
    return;
  }

  # if the hello-source-address wasn't configured, check that the
  # interface has an IPv4 address configured on it.
  my $primary_addr = vrrp_get_primary_addr($ifname);
  if ( ! defined $primary_addr ) {
    vrrp_log("no primary or hello-source");
    return "must configure either a primary address on [$ifname] or"
      . " a hello-source-address\n";
  }
  return;
}

sub get_ctsync_syncgrp {
  my ($origfunc) = @_;
  my $failover_sync_grp = undef;

  my $listnodesfunc = "listNodes";
  my $returnvalfunc = "returnValue";
  if ( defined $origfunc ) {
    $listnodesfunc = "listOrigNodes";
    $returnvalfunc = "returnOrigValue";
  }

  my @failover_mechanism =
    Vyatta::ConntrackSync::get_conntracksync_val( $listnodesfunc,
    "failover-mechanism" );

  if ( defined $failover_mechanism[0] && $failover_mechanism[0] eq 'vrrp' ) {
    $failover_sync_grp =
      Vyatta::ConntrackSync::get_conntracksync_val( $returnvalfunc,
      "failover-mechanism $failover_mechanism[0] sync-group" );
  }
  return $failover_sync_grp;
}

sub keepalived_get_values {
  my ( $intf, $path , $noerr) = @_;

  my @loc;
  my $err;
  my @errs   = ();
  my $output = '';
  my $config = new Vyatta::Config;

  my $state_transition_script = get_state_script();

  my $on_off = "off";
  $on_off = "on" if $noerr;
  vrrp_log("keepalived_get_values [$intf][$path] noerr = $on_off");
  $config->setLevel($path);
  if ( $config->isDeleted("vrrp") ) {
      return ($output, @errs) if $noerr;
      vrrp_log("vrrp_instance [$intf] deleted");
      return ( $output, @errs );      
  }

  $config->setLevel("$path vrrp vrrp-group");
  my @groups = $config->listNodes();
  if (scalar(@groups) < 1) {
      return ($output, @errs) if $noerr;
      @loc = split(/ /, "$path vrrp vrrp-group");
      $err = "must define a vrrp-group";
      Vyatta::Config::outputError(\@loc, $err);
      push @errs, $err;
      return ( $output, @errs );      
  }
  foreach my $group (@groups) {
    my $vrrp_instance = "vyatta-$intf-$group";
    $config->setLevel("$path vrrp vrrp-group $group");
    if ( $config->exists("disable") ) {
      next if $noerr;
      vrrp_log("$vrrp_instance disabled - skipping");
      my $state_file = get_state_file( $intf, $group );
      unlink($state_file);
      next;
    }
    my @vips     = $config->returnValues("virtual-address");
    my $num_vips = scalar(@vips);
    if ( $num_vips == 0 ) {
      next if $noerr;
      @loc = split(/ /, "$path vrrp vrrp-group $group");
      $err = "must define a virtual-address for vrrp-group $group";
      Vyatta::Config::outputError(\@loc, $err);
      push @errs, $err;
      next;
    }
    if ( $num_vips > 20 ) {
      next if $noerr;
      @loc = split(/ /, "$path vrrp vrrp-group $group");
      $err = "can not set more than 20 VIPs per group";
      Vyatta::Config::outputError(\@loc, $err);
      push @errs, $err;
      next;
    }

    my $use_vmac = 0;
    my $transition_intf = $intf;
    if ( $config->exists("interface") ) {
	$use_vmac = 1;
        $transition_intf = "$intf"."v"."$group";
    }

    my $priority = $config->returnValue("priority");
    if ( !defined $priority ) {
      $priority = 100; # Default backup priority is 100 from RFC.
    }
    my $address_owner = 0;
    $address_owner = 1 if ($priority == 255 && $use_vmac == 1);
    my $preempt = $config->returnValue("preempt");
    if (defined $preempt && $address_owner == 1){
      if ($preempt ne "true") { # the handling of default in configuration is odd so we need to allow it to be set to true...
         $err = "cannot define preempt if this is the address owner";
         if ( defined $err ) {
           next if $noerr;
           @loc = split(/ /, "$path vrrp vrrp-group $group");
           Vyatta::Config::outputError(\@loc, $err);
           push @errs, $err;
           next;
         }
      }
    }
    if ( !defined $preempt ) {
      $preempt = "true";
    }
    my $preempt_delay = $config->returnValue("preempt-delay");
    if ( defined $preempt_delay and $preempt eq "false" ) {
      print "Warning: preempt delay is ignored when preempt=false\n";
    }
    my $advert_int = $config->returnValue("advertise-interval");
    if ( !defined $advert_int ) {
      $advert_int = 1;
    }
    my $sync_group = $config->returnValue("sync-group");
    if ( defined $sync_group && $sync_group ne "" ) {
      push @{ $HoA_sync_groups{$sync_group} }, $vrrp_instance;
    }
    my $hello_source_addr = $config->returnValue("hello-source-address");
    $err = validate_source_addr( $intf, $hello_source_addr ) if (!$address_owner == 1);
    if ( defined $err ) {
      next if $noerr;
      @loc = split(/ /, "$path vrrp vrrp-group $group");
      Vyatta::Config::outputError(\@loc, $err);
      push @errs, $err;
      next;
    }
    if (defined $hello_source_addr && $address_owner == 1){
       $err = "cannot define hello-source-address if this is the address owner";
       if ( defined $err ) {
         next if $noerr;
         @loc = split(/ /, "$path vrrp vrrp-group $group");
         Vyatta::Config::outputError(\@loc, $err);
         push @errs, $err;
         next;
       }
    } elsif ($address_owner == 1) {
      $hello_source_addr = $vips[0];
      $hello_source_addr =~ s/(.*?)\/.*/$1/;
    } 

    $config->setLevel("$path vrrp vrrp-group $group");
    my ($auth_type, $auth_pass) = (undef, undef);
    if ($config->exists('authentication')) {
      $config->setLevel("$path vrrp vrrp-group $group authentication");
      $auth_type = $config->returnValue("type");
      $auth_pass = $config->returnValue("password");
      if ( defined $auth_type ) {
        $auth_type = "PASS" if $auth_type eq "plaintext-password";
        $auth_type = uc($auth_type);
        if ( !defined $auth_pass ) {
          next if $noerr;
          @loc = split(/ /, "$path vrrp vrrp-group $group");
          $err = "vrrp authentication password not set";
          Vyatta::Config::outputError(\@loc, $err);
          push @errs, $err;
          next;
        }
      } else {
        next if $noerr;
        @loc = split(/ /, "$path vrrp vrrp-group $group");
        $err = "vrrp authentication type not set";
        Vyatta::Config::outputError(\@loc, $err);
        push @errs, $err;
        next;
      }
    } 

    $config->setLevel("$path vrrp vrrp-group $group run-transition-scripts");
    my $run_backup_script = $config->returnValue("backup");
    if ( !defined $run_backup_script ) {
      $run_backup_script = "null";
    }
    my $run_fault_script = $config->returnValue("fault");
    if ( !defined $run_fault_script ) {
      $run_fault_script = "null";
    }
    my $run_master_script = $config->returnValue("master");
    if ( !defined $run_master_script ) {
      $run_master_script = "null";
    }

    # We now have the values and have validated them, so
    # generate the config.

    $output .= "vrrp_instance $vrrp_instance \{\n";
    my $init_state;
    if ( defined $ctsync ) {

      # check if this group is part of conntrack-sync vrrp sync-group
      my $ctsync_syncgrp = get_ctsync_syncgrp();
      my $vrrpsyncgrp =
        list_vrrp_sync_group( $intf, $group, 'returnOrigPlusComValue' );
      if ( defined $ctsync_syncgrp
        && defined $vrrpsyncgrp
        && ( $ctsync_syncgrp eq $vrrpsyncgrp ) )
      {
        $init_state = 'BACKUP';
      } else {
        $init_state = vrrp_get_init_state( $intf, $group, $vips[0], $preempt );
      }
    } else {
      $init_state = vrrp_get_init_state( $intf, $group, $vips[0], $preempt );
    }
    $output .= "\tstate $init_state\n";
    $output .= "\tinterface $intf\n";
    $output .= "\tvirtual_router_id $group\n";
    if ($use_vmac) {
	$output .= "\tuse_vmac $intf";
	$output .= "v";
	$output .= "$group\n";
    }
    $output .= "\tpriority $priority\n";
    if ( $preempt eq "false" ) {
      $output .= "\tnopreempt\n";
    }
    if ( defined $preempt_delay ) {
      $output .= "\tpreempt_delay $preempt_delay\n";
    }
    $output .= "\tadvert_int $advert_int\n";
    if ( defined $auth_type ) {
      $output .= "\tauthentication {\n";
      $output .= "\t\tauth_type $auth_type\n";
      $output .= "\t\tauth_pass $auth_pass\n\t}\n";
    }
    if ( defined $hello_source_addr ) {
      $output .= "\tmcast_src_ip $hello_source_addr\n";
    }
    $output .= "\tvirtual_ipaddress \{\n";
    foreach my $vip (@vips) {
      $output .= "\t\t$vip\n";
    }
    $output .= "\t\}\n";
    $output .= "\tnotify_master \"$state_transition_script master ";
    $output .= "$intf $group $transition_intf \'$run_master_script\' @vips\" \n";
    $output .= "\tnotify_backup \"$state_transition_script backup ";
    $output .= "$intf $group $transition_intf \'$run_backup_script\' @vips\" \n";
    $output .= "\tnotify_fault \"$state_transition_script fault ";
    $output .= "$intf $group $transition_intf \'$run_fault_script\' @vips\" \n";
    $output .= "\}\n\n";
  }

  return ( $output, @errs );
}

sub vrrp_get_sync_groups {

  my $output = "";

  foreach my $sync_group ( keys %HoA_sync_groups ) {
    $output .= "vrrp_sync_group $sync_group \{\n\tgroup \{\n";
    foreach my $vrrp_instance ( 0 .. $#{ $HoA_sync_groups{$sync_group} } ) {
      $output .= "\t\t$HoA_sync_groups{$sync_group}[$vrrp_instance]\n";
    }
    $output .= "\t\}\n";

    ## add conntrack-sync part here if configured ##
    my $origfunc = undef;
    $origfunc = 'true' if !defined $ctsync;
    my $failover_sync_grp = get_ctsync_syncgrp($origfunc);
    if ( defined $failover_sync_grp && $failover_sync_grp eq $sync_group ) {
      $output .= "\tnotify_master \"$ctsync_script master $sync_group\"\n";
      $output .= "\tnotify_backup \"$ctsync_script backup $sync_group\"\n";
      $output .= "\tnotify_fault \"$ctsync_script fault $sync_group\"\n";
    }
    $output .= "\}\n";
  }
  return $output;
}

sub vrrp_read_changes {
  my @lines = ();
  return @lines if !-e $changes_file;
  open( my $FILE, "<", $changes_file ) or die "Error: read $!";
  @lines = <$FILE>;
  close($FILE);
  chomp @lines;
  return @lines;
}

sub vrrp_save_changes {
  my @list = @_;

  my $num_changes = scalar(@list);
  vrrp_log("saving changes file $num_changes");
  open( my $FILE, ">", $changes_file ) or die "Error: write $!";
  print $FILE join( "\n", @list ), "\n";
  close($FILE);
}

sub vrrp_find_changes {

  my @list           = ();
  my $config         = new Vyatta::Config;
  my $vrrp_instances = 0;

  foreach my $name ( getInterfaces() ) {
    my $intf = new Vyatta::Interface($name);
    next unless $intf;
    my $path = $intf->path();
    $config->setLevel($path);
    if ( $config->exists("vrrp") ) {
      my %vrrp_status_hash = $config->listNodeStatus("vrrp");
      my ( $vrrp, $vrrp_status ) = each(%vrrp_status_hash);
      if ( $vrrp_status ne "static" ) {
        push @list, $name;
        vrrp_log("$vrrp_status found $name");
      }
    }

    #
    # Now look for deleted from the origin tree
    #
    $config->setLevel($path);
    if ( $config->isDeleted("vrrp") ) {
      push @list, $name;
      vrrp_log("Delete found $name");
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
  if ( scalar(@lines) < 1 ) {

    #
    # we shouldn't get to this point, but try to handle it if we do
    #
    vrrp_log("unexpected remove_from_changes()");
    unlink($changes_file);
    return 0;
  }
  my @new_lines = ();
  foreach my $line (@lines) {
    if ( $line =~ /$intf$/ ) {
      vrrp_log("remove_from_changes [$line]");
    } else {
      push @new_lines, $line;
    }
  }

  my $num_changes = scalar(@new_lines);
  if ( $num_changes > 0 ) {
    vrrp_save_changes(@new_lines);
  } else {
    unlink($changes_file);
  }
  return $num_changes;
}

sub vrrp_update_config {

  my @errs   = ();
  my $output;

  my $config         = new Vyatta::Config;
  my $vrrp_instances = 0;

  %HoA_sync_groups = ();
  foreach my $name ( getInterfaces() ) {
    my $intf = new Vyatta::Interface($name);
    next unless $intf;
    my $path = $intf->path();
    $config->setLevel($path);
    if ( $config->exists("vrrp") ) {

      #
      # keepalived gets real grumpy with interfaces that
      # don't exist, so skip vlans that haven't been
      # instantiated yet (typically occurs at boot up).
      #
      if ( !( -d "/sys/class/net/$name" ) ) {
        push @errs, "$name doesn't exist";
        next;
      }
      my ( $inst_output, @inst_errs ) = keepalived_get_values( $name, $path, 1 );
      if ( scalar(@inst_errs) ) {
        push @errs, @inst_errs;
      } else {
        $output .= $inst_output;
        $vrrp_instances++;
      }
    }
  }

  if ( $vrrp_instances > 0 ) {
    my $sync_groups = vrrp_get_sync_groups();
    if ( defined $sync_groups && $sync_groups ne "" ) {
      $output = $sync_groups . $output;
    }
    $output = "global_defs {\n\tenable_traps\n}\n" . $output;
    $output = "#\n# autogenerated by $0\n#\n\n" . $output;
    keepalived_write_file( $conf_file, $output );
  }
  return ( $vrrp_instances, @errs );
}

sub keepalived_write_file {
  my ( $file, $data ) = @_;

  open( my $fh, '>', $file ) || die "Couldn't open $file - $!";
  print $fh $data;
  close $fh;
}

#
# main
#
GetOptions(
  "vrrp-action=s" => \$action,
  "intf=s"        => \$vrrp_intf,
  "group=s"       => \$vrrp_group,
  "vip=s"         => \$vrrp_vip,
  "ctsync=s"      => \$ctsync,
);

if ( !defined $action ) {
  print "no action\n";
  exit 1;
}


#
# run op mode command first
#
if ( $action eq "list-vrrp-intf" ) {
  my @intfs = list_vrrp_intf();
  print join( ' ', @intfs );
  exit 0;
}

if ( $action eq "list-vrrp-group" ) {
  if ( !defined $vrrp_intf ) {
    print "must include interface\n";
    exit 1;
  }
  my @groups = list_vrrp_group($vrrp_intf);
  print join( ' ', @groups );
  exit 0;
}

#
# end of op mode commands
#


#
# This script can be called from two places :
# 1. a vrrp node under one of the interfaces
# 2. service conntrack-sync when conntrack-sync uses VRRP as failover-mechanism
#
# when called from conntrack-sync; we just need to add/remove config 
# for sync-group transition scripts and restart daemon. We do NOT 
# perform any other actions usually done in the update part of this 
# script otherwise 
#

if ( !defined $ctsync ) {

  # make sure sync-group used by ctsync has not been deleted

  my $failover_sync_grp = get_ctsync_syncgrp();
  if ( defined $failover_sync_grp ) {

    # make sure vrrp sync-group exists
    my $sync_grp_exists = 'false';
    my @vrrp_intfs      = list_vrrp_intf('exists');
    foreach my $vrrp_intf (@vrrp_intfs) {
      my @vrrp_groups = list_vrrp_group( $vrrp_intf, 'listNodes' );
      foreach my $vrrp_group (@vrrp_groups) {
        my $sync_grp =
          list_vrrp_sync_group( $vrrp_intf, $vrrp_group, 'returnValue' );
        if ( defined $sync_grp && $sync_grp eq "$failover_sync_grp" ) {
          $sync_grp_exists = 'true';
          last;
        }
      }
      last if $sync_grp_exists eq 'true';
    }

    if ( $sync_grp_exists eq 'false' ) {
      print "sync-group $failover_sync_grp used for conntrack-sync"
        . " is either deleted or undefined\n";
      exit 1;
    }
  }

}

#
# UPDATE action: the logic for "update" is far more complex than it should
# be due to limitations of the @&!#ing cli.  Ideally we would have just one
# end node at the top level 'interfaces' level.  That way we would know that
# all the vif's and bond interfaces have been created and we could call this
# function once to generate the entire keepalived conf file and restart the
# daemon 1 time.  Unfortuately the cli doesn't support nested end nodes, so
# we have to put and end node at every vrrp node and call this function for
# every vrrp instance, but since we only want to start the daemon once we 
# need to keep track of some state.  The first call checks if the "changes"
# file exists, if not it search for all the vrrp instances that have changed
# and adds them to the changes file.  As each instance is processed it is
# removed from changes and when there are no more changes the daemon is
# started/restarted/stopped.  Now since we need to run the script for each 
# instance, we can NOT do "commit" checks in the node.def files since that
# prevents the end node from getting called.  So all the validation needs to
# be in this script, but why not just do all the work once when the changes 
# file is empty?  Well the problem then becomes that when the validation 
# fails, the non-zero exit needs to be associated with the end node otherwise
# the cli will assume it's good push it through to the active config.  So
# we need to do only the validation for the instance being processed and 
# then on the last instance generate the full conf file and signal the daemon
# if any changes have been made even if the last instance has a non-zero exit.
#
if ( $action eq "update" ) {
  $changes_file = get_changes_file();
  $conf_file    = get_conf_file();
  vrrp_log("vrrp update $vrrp_intf")     if defined $vrrp_intf;
  if ( !-e $changes_file ) {
    my $num_changes = vrrp_find_changes();
    if ( $num_changes == 0 ) {
      #
      # Shouldn't happen, but ...
      # - one place were this has been know to occur is if a vif is deleted
      #   that has a vrrp instance under it.  Because the cli doesn't 
      #   reverse priorities on delete, then the vrrp under the vif
      #   is gone by the time we get here.
      #
      vrrp_log("unexpected 0 changes");
    }
  }
   
  my $intf = new Vyatta::Interface($vrrp_intf);
  if (! defined $intf) {
      die "Error: invalid interface [$vrrp_intf]";
  }
  my $path = $intf->path();
  my ( $inst_output, @inst_errs ) = keepalived_get_values( $vrrp_intf, $path );
  my $more_changes = remove_from_changes($vrrp_intf);
  vrrp_log("more changes $more_changes");

  if ( $more_changes == 0 ) {
      my ( $vrrp_instances, @errs ) = vrrp_update_config();
      vrrp_log("instances $vrrp_instances");
      if ( $vrrp_instances > 0 ) {
          restart_daemon($conf_file);
          # The changes_file should already be gone by this point, but 
          # this is the "belt & suspenders" approach.
          unlink($changes_file);
          vrrp_log("end transaction\n");
      } elsif ( $vrrp_instances == 0 ) {
          stop_daemon();
          unlink($conf_file);
          unlink($changes_file);
          vrrp_log("end transaction\n");
      }
  }
  if ( scalar(@inst_errs) ) {
    vrrp_log( join( "\n", @inst_errs ) );
    exit 1;
  }
  exit 0;
}

if ( $action eq "update-ctsync" ) {
    vrrp_log("vrrp update conntrack-sync");
    $conf_file = get_conf_file();
    my ( $vrrp_instances, @errs ) = vrrp_update_config();
    vrrp_log("instances $vrrp_instances");
    if ($vrrp_instances > 0) {
        restart_daemon($conf_file);
    } 
    exit 0;
}

if ( $action eq "delete" ) {
  if ( !defined $vrrp_intf || !defined $vrrp_group ) {
    print "must include interface & group";
    exit 1;
  }
  vrrp_log("vrrp delete $vrrp_intf $vrrp_group");
  my $state_file = get_state_file( $vrrp_intf, $vrrp_group );
  unlink($state_file);
  exit 0;
}

exit 0;

# end of file
