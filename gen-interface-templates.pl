#!/usr/bin/perl
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
# Author: Stephen Hemminger
# Date: March 2009
# Description: Script to automatically generate per-interface arp options
#              templates.
#
# **** End License ****

use strict;
use warnings;

# set DEBUG in environment to test script
my $debug = $ENV{'DEBUG'};

# Mapping from configuration level to ifname used AT THAT LEVEL
my %interface_hash = (
    'ethernet/node.tag'                                           => '$VAR(@)',
    'ethernet/node.tag/vif/node.tag'                              => '$VAR(../@).$VAR(@)',
    'ethernet/node.tag/vif/node.tag/vif/node.tag'                 => '$VAR(../../@).$VAR(../@).$VAR(@)',
    'wireless/node.tag'                                           => '$VAR(@)',
    'wireless/node.tag/vif/node.tag'                              => '$VAR(../@).$VAR(@)',
    'pseudo-ethernet/node.tag'                                    => '$VAR(@)',
    'pseudo-ethernet/node.tag/vif/node.tag'                       => '$VAR(../@).$VAR(@)',
    'pseudo-ethernet/node.tag/vif/node.tag/vif/node.tag'          => '$VAR(../../@).$VAR(../@).$VAR(@)',
    'bonding/node.tag'                                            => '$VAR(@)',
    'bonding/node.tag/vif/node.tag'                               => '$VAR(../@).$VAR(@)',
    'bonding/node.tag/vif/node.tag/vif/node.tag'                  => '$VAR(../../@).$VAR(../@).$VAR(@)',
    'tunnel/node.tag'                                             => '$VAR(@)',
    'bridge/node.tag'                                             => '$VAR(@)',
);

# Hash table to check if the priority needs to set @ root
# of the node.def which is generated.
my %interface_prio = (
    'vti/node.tag' => '901',
);

sub gen_template {
    my ( $inpath, $outpath, $ifname, $gen_prio, $prio, $depth ) = @_;

    print $outpath, "\n" if ($debug);
    opendir my $d, $inpath
      or die "Can't open: $inpath:$!";

    # walk through sample templates
    foreach my $name ( grep { !/^\./ } readdir $d ) {
        my $in  = "$inpath/$name";
        my $out = "$outpath/$name";

	# recurse into subdirectory
        if ( -d $in ) {
            my $subif = $ifname;
            $subif =~ s#@\)#../@)#g if ($name ne 'node.tag');

            ( -d $out )
              or mkdir($out)
              or die "Can't create $out: $!";

            gen_template( $in, $out, $subif, $gen_prio, $prio, $depth+1);
            next;
        }

        print "in: $in out: $out\n" if ($debug);
        open my $inf,  '<', $in  or die "Can't open $in: $!";
        open my $outf, '>', $out or die "Can't open $out: $!";

        # For the top node.tag create the priority tag.
        if ($name eq 'node.def' && $gen_prio == 1 && $depth <= 1) {
            print $outf "priority: $prio\n";
        }
        while ( my $line = <$inf> ) {
            $line =~ s#\$IFNAME#$ifname#;
            print $outf $line;
        }
        close $inf;
        close $outf or die "Close error $out:$!";
    }
    closedir $d;
}

sub mkdir_p {
    my $path = shift;

    return 1 if ( mkdir($path) );

    my $pos = rindex( $path, "/" );
    return unless $pos != -1;
    return unless mkdir_p( substr( $path, 0, $pos ) );
    return mkdir($path);
}

die "Usage: $0 output_directory\n" if ($#ARGV < 0);

my $outdir = $ARGV[0];

foreach my $if_tree ( keys %interface_hash ) {
    my $inpath  = "interface-templates";
    my $outpath = "$outdir/interfaces/$if_tree";
    ( -d $outpath )
      or mkdir_p($outpath)
      or die "Can't create $outpath:$!";

    my $gen_prio = 0;
    my $prio = 0;
    $gen_prio = 1  if (exists $interface_prio{ $if_tree });
    if ($gen_prio == 1) {
        $prio = $interface_prio{ $if_tree };
    }

    gen_template( $inpath, $outpath, $interface_hash{$if_tree},
                 $gen_prio, $prio, 0 );
}
