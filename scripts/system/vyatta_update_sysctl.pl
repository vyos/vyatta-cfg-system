#!/usr/bin/perl
#
# Module: vyatta_update_sysctl.pl
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
# A copy of the GNU General Public License is available as
# `/usr/share/common-licenses/GPL' in the Debian GNU/Linux distribution
# or on the World Wide Web at `http://www.gnu.org/copyleft/gpl.html'.
# You can also obtain it by writing to the Free Software Foundation,
# Free Software Foundation, Inc., 51 Franklin St, Fifth Floor, Boston,
# MA 02110-1301, USA.
# 
# This code was originally developed by Vyatta, Inc.
# Portions created by Vyatta are Copyright (C) 2007 Vyatta, Inc.
# All Rights Reserved.
# 
# Author: Jason Hendry
# Date: October 2014
# Description: Script to manage sysctl values
# 
# **** End License ****
#

use lib "/opt/vyatta/share/perl5/";
use Vyatta::Config;
use Vyatta::File qw(touch);

use Getopt::Long;

use strict;
use warnings;

my $SYSCTL = '/sbin/sysctl';

my (@opts);

sub usage {
    print <<EOF;
Usage: $0 --option=<sysctl_option> <value>
EOF
    exit 1;
}

GetOptions(
            "option=s{2}"             => \@opts,
            ) or usage();

set_sysctl_value(@opts) if (@opts);
exit 0;

sub set_sysctl_value {
    my ($sysctl_opt, $nvalue) = @_;
    my $ovalue = get_sysctl_value($sysctl_opt);

    if ($nvalue ne $ovalue) {
        my $cmd = "$SYSCTL -w $sysctl_opt=$nvalue 2>&1 1>&-";
        system($cmd);
        if ($? >> 8) {
            die "exec of $SYSCTL failed: '$cmd'";
        } 
    }
}

sub get_sysctl_value {
    my $option = shift;
    my $val;

    open( my $sysctl, '-|', "$SYSCTL $option 2>&1" ) or die "sysctl failed: $!\n";
    while (<$sysctl>) {
        chomp;
        $val = (split(/ = /, $_))[1];
    }
    close $sysctl;
    return ($val);
}

# net.ipv4.ipfrag_time
