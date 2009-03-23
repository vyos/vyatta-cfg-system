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
# Portions created by Vyatta are Copyright (C) 2007 Vyatta, Inc.
# All Rights Reserved.
#
# **** End License ****

use strict;
use warnings;

use lib "/opt/vyatta/share/perl5";
use Vyatta::Config;

# Exit codes form useradd.8 man page
my %reasons = (
    0  => 'success',
    1  => 'can´t update password file',
    2  => 'invalid command syntax',
    3  => 'invalid argument to option',
    4  => 'UID already in use (and no -o)',
    6  => 'specified group doesn´t exist',
    9  => 'username already in use',
    10 => 'can´t update group file',
    12 => 'can´t create home directory',
    13 => 'can´t create mail spool',
);

# Map of level to additional groups
my %level_map = (
    'admin'    => [ 'quaggavty', 'vyattacfg', 'sudo', 'adm', 'dip', 'disk' ],
    'operator' => [ 'quaggavty', 'operator',  'adm',  'dip', ],
);

# Construct a map from existing users to group membership
# Use space seperated format
my %group_map;

while ( my ( $name, undef, undef, $members ) = getgrent() ) {
    foreach my $user ( split / /, $members ) {
        my $g = $group_map{$user};
        if ($g) {
            my @l = split / /, $g;
            push @l, $name;
            $group_map{$user} = join( ' ', sort @l );
        }
        else {
            $group_map{$user} = $name;
        }

    }
}

my $uconfig = new Vyatta::Config;
$uconfig->setLevel("system login user");
my %users = $uconfig->listNodeStatus();

# we have some users
for my $user ( keys %users ) {
    my $status = $users{$user};

    if ( $status eq 'deleted' ) {
        if ( $user eq 'root' ) {
            warn "User \"root\" can really be deleted\n";
        }
        else {
            system("sudo userdel -r '$user'") == 0
              or die "userdel failed: $?\n";
        }
    }
    elsif ( $status eq 'added' || $status eq 'changed' ) {
        $uconfig->setLevel("system login user $user");
        my $pwd = $uconfig->returnValue('authentication encrypted-password');
        $pwd or die "Encrypted password not in configuration for $user";

        my $level = $uconfig->returnValue('level');
        $level or die "Level not defined for $user";

        # map level to group membership
        my @groups = @{ $level_map{$level} };

        # add any additional groups from configuration
        push( @groups, $uconfig->returnValues('group') );

        my $fname = $uconfig->returnValue('full-name');
        my $home  = $uconfig->returnValue('home-directory');

        # Read existing settings
        my (
            undef,    $opwd, $uid, $gid,   undef,
            $comment, undef, $dir, $shell, undef
        ) = getpwnam($user);

        my $cmd;

        # not found in existing passwd, must be new
        if ( !defined $uid ) {

            # make new user using vyatta shell
            #  and make home directory (-m)
            #  and with default group of 100 (users)
            $cmd = 'useradd -s /bin/vbash -m -N';
        }
        else {

            # If no part of password or group file changed
            # then there is nothing to do here.
            next
              if ( $opwd eq $pwd
                && ( !$fname || $fname eq $comment )
                && ( !$home  || $home  eq $dir )
                && join( ' ', sort @groups ) eq $group_map{$user} );

            $cmd = "usermod";
        }

        $cmd .= " -p '$pwd'";
        $cmd .= " -c \"$fname\"" if ( defined $fname );
        $cmd .= " -d \"$home\"" if ( defined $home );
        $cmd .= ' -G ' . join( ',', @groups );
        system("sudo $cmd $user") == 0
          or die "sudo $cmd $user failed: $?";
    }
}

exit 0;
