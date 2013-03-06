#!/usr/bin/perl

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
# **** End License ****

use strict;
use warnings;

foreach my $name (@ARGV) {
    die "$name : illegal characters in name\n"
	if (!($name =~ /^[a-zA-Z0-9]*$/));

    # Usernames may only be up to 32 characters long.
    die "$name: name may only be up to 32 characters long\n"
	if (length($name) > 32);
}

exit 0;
