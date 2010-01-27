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

my $passwdFile = '/etc/passwd';

# Lookup user in password file which may not give same
# result as getpw* which uses NSS
sub finduser {
    my $user = shift;
    my $uid;

    open( my $f, '<', $passwdFile )
      or die "Can't open $passwdFile: $!";

    while (<$f>) {
        chomp;
        my ( $name, undef, $id ) = split /:/;

        next unless ( $name eq $user );
	$uid = $id;
	last;
    }
    close $f;

    return $uid;
}

foreach my $user (@ARGV) {
    my $uid = getpwnam($user);

    # User does not exist in system, its okay
    next unless defined($uid);

    # System accounts should not be listed in vyatta configuration
    # 1000 is SYS_UID_MIN
    die "$user : account is already reserved for system use\n"
	if ($uid > 0 && $uid < 1000);

    my $pwuid = finduser($user);
    
    die "$user : account exists but is not local (change on server)\n"
	unless defined ($pwuid);

    die "$user : exists but has different uid on local versus remote\n"
	unless ($pwuid eq $uid);
}

exit 0;
