#!/usr/bin/env perl
# **** License ****
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 2 or later as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# This code was originally developed by VyOS Development Group
# All Rights Reserved.
#
# Author:       Daniil Baturin <daniil@baturin.org>
# Description:  Check if we are running on an EC2 instance.
#               If both system UUID and system serial number start with "EC2",
#               most likely we are.
#
# **** End License ****


use strict;
use warnings;

my $DMIDECODE = "/usr/sbin/dmidecode";

my $SN = `$DMIDECODE -s system-serial-number`;

if( $SN =~ /^ec2.*/i )
{
    exit(0);
}
else
{
    exit(1);
}

