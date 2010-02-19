#!/usr/bin/perl
#
# Module: vyatta-bridgegroup-dependency.pl
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
# Portions created by Vyatta are Copyright (C) 2010 Vyatta, Inc.
# All Rights Reserved.
#
# Author: Mohit Mehta
# Date: February 2010
# Description: To check dependency between bridge and interfaces assigned to it
#
# **** End License ****
#

use lib "/opt/vyatta/share/perl5/";
use Vyatta::Config;
use Vyatta::Misc;
use Getopt::Long;
use POSIX;

use strict;
use warnings;

sub check_bridge_interfaces {
  my $bridge_intf = shift;
  foreach my $name ( Vyatta::Misc::getInterfaces() ) {
    my $intf = new Vyatta::Interface($name);
    next unless $intf;
    my $intf_bridge = undef;
    $intf_bridge = $intf->bridge_grp();
    if (defined $intf_bridge && $intf_bridge eq $bridge_intf) {
      return "Interfaces are still assigned to bridge $bridge_intf";
    }
  }
  return;
}

sub is_bridge_deleted {
  my $bridge_name = shift;
  my $config = new Vyatta::Config;
  my @bridge_intfs = $config->listNodes("interfaces bridge");
  my @orig_bridge_intfs = $config->listOrigNodes("interfaces bridge");
  if (scalar(grep(/^$bridge_name$/, @bridge_intfs)) == 0) {
    if (scalar(grep(/^$bridge_name$/, @orig_bridge_intfs)) > 0) { 
      # bridge deleted in proposed config
      return;
    }
  }
  exit 1;
}

#
# main
#

my ($error, $warning);
my ($no_interfaces_assigned, $bridge_interface, $bridge_notin_proposedcfg);

GetOptions( "no-interfaces-assigned!"  	=> \$no_interfaces_assigned,
            "bridge-interface=s"        => \$bridge_interface,
            "bridge-notin-proposedcfg!" => \$bridge_notin_proposedcfg);

die "undefined bridge interface" if ! defined $bridge_interface;

($error, $warning) =  check_bridge_interfaces($bridge_interface)
                      if ($no_interfaces_assigned);

($error, $warning) =  is_bridge_deleted($bridge_interface)
                      if ($bridge_notin_proposedcfg);

if (defined $warning) {
  print "$warning\n";
}

if (defined $error) {
  print "$error\n";
  exit 1;
}

exit 0;
