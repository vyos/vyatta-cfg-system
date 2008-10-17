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
use lib "/opt/vyatta/share/perl5";
use VyattaConfig;

# handle "user"
my $uconfig = new VyattaConfig;
$uconfig->setLevel("system login user");

my %users     = $uconfig->listNodeStatus();
my @user_keys = sort keys %users;

if (   ( scalar(@user_keys) <= 0 )
    || !( grep /^root$/, @user_keys )
    || ( $users{'root'} eq 'deleted' ) )
{

    # root is deleted
    print STDERR "User \"root\" cannot be deleted\n";
    exit 1;
}

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
    'admin'    => [ 'quaggavty', 'vyattacfg', 'sudo', 'adm', 'dip', ],
    'operator' => [ 'quaggavty', 'operator',  'adm', 'dip', ],
);

# we have some users
for my $user (@user_keys) {
    if ( $users{$user} eq 'deleted' ) {
        system("sudo userdel -r '$user'");
        die "userdel failed\n" if ( $? >> 8 );
    }
    elsif ( $users{$user} eq 'added' || $users{$user} eq 'changed' ) {
        $uconfig->setLevel("system login user $user");

        # See if this is a modification of existing account
        my (undef, undef, $uid,  undef,  undef,
            undef, undef, undef, $shell, undef) = getpwnam($user);

        my $cmd;
	# not found in existing passwd, must be new
        if ( !defined $uid ) {
	    # make new user using vyatta shell
	    #  and make home directory (-m)
            #  and with default group of 100 (users)
            $cmd = 'useradd -s /bin/vbash -m -N';
        }
	# TODO Add checks for attempts to put system users
 	# in configuration file 

	# TODO Check if nothing changed and just skip
        else {
            $cmd = "usermod";
        }

        my $pwd   = $uconfig->returnValue('authentication encrypted-password');
        $pwd or die 'encrypted password not set';
        $cmd .= " -p '$pwd'";

        my $fname = $uconfig->returnValue('full-name');
        $cmd .= " -c \"$fname\"" if ( defined $fname );

        my $home = $uconfig->returnValue('home-directory');
        $cmd .= " -d \"$home\"" if ( defined $home );

	# map level to group membership
        my $level  = $uconfig->returnValue('level');
        my $gref   = $level_map{$level};
        my @groups = @{$gref};

	# add any additional groups from configuration
        push( @groups, $uconfig->returnValues('group') );

        $cmd .= ' -G ' . join( ',', @groups );

        system("sudo $cmd $user");
        if ( $? == -1 ) {
            die "failed to exec $cmd";
        }
        elsif ( $? & 127 ) {
            die "$cmd died with signal" . ( $? & 127 );
        }
        elsif ( $? != 0 ) {
            my $reason = $reasons{ $? >> 8 };
            die "$cmd failed: $reason\n";
        }
    }
}

my $PAM_RAD_CFG   = '/etc/pam_radius_auth.conf';
my $PAM_RAD_BEGIN = '# BEGIN Vyatta Radius servers';
my $PAM_RAD_END   = '# END Vyatta Radius servers';

sub is_pam_radius_present {
    if ( !open( AUTH, '/etc/pam.d/common-auth' ) ) {
        print STDERR "Cannot open /etc/pam.d/common-auth\n";
        exit 1;
    }
    my $present = 0;
    while (<AUTH>) {
        if (/\ssufficient\spam_radius_auth\.so$/) {
            $present = 1;
            last;
        }
    }
    close AUTH;
    return $present;
}

sub remove_pam_radius {
    return 1 if ( !is_pam_radius_present() );
    my $cmd =
        'sudo sh -c "'
      . 'sed -i \'/\tsufficient\tpam_radius_auth\.so$/d;'
      . '/\tpam_unix\.so /{s/ use_first_pass$//}\' '
      . '/etc/pam.d/common-auth && '
      . 'sed -i \'/\tsufficient\tpam_radius_auth\.so$/d\' '
      . '/etc/pam.d/common-account"';
    system($cmd);
    return 0 if ( $? >> 8 );
    return 1;
}

sub add_pam_radius {
    return 1 if ( is_pam_radius_present() );
    my $cmd =
        'sudo sh -c "'
      . 'sed -i \'s/^\(auth\trequired\tpam_unix\.so.*\)$'
      . '/auth\tsufficient\tpam_radius_auth.so\n\1 use_first_pass/\' '
      . '/etc/pam.d/common-auth && '
      . 'sed -i \'s/^\(account\trequired\tpam_unix\.so.*\)$'
      . '/account\tsufficient\tpam_radius_auth.so\n\1/\' '
      . '/etc/pam.d/common-account"';
    system($cmd);
    return 0 if ( $? >> 8 );
    return 1;
}

sub remove_radius_servers {
    system( "sudo sed -i '/^$PAM_RAD_BEGIN\$/,/^$PAM_RAD_END\$/{d}' "
          . "$PAM_RAD_CFG" );
    return 0 if ( $? >> 8 );
    return 1;
}

sub add_radius_servers {
    my $str = shift;
    system( "sudo sh -c \""
          . "echo '$PAM_RAD_BEGIN\n$str$PAM_RAD_END\n' >> $PAM_RAD_CFG\"" );
    return 0 if ( $? >> 8 );
    return 1;
}

# handle "radius-server"
my $rconfig = new VyattaConfig;
$rconfig->setLevel("system login radius-server");
my %servers     = $rconfig->listNodeStatus();
my @server_keys = sort keys %servers;
if ( scalar(@server_keys) <= 0 ) {

    # all radius servers deleted
    exit 1 if ( !remove_pam_radius() );
    exit 0;
}

# we have some servers
my $all_deleted = 1;
my $server_str  = '';
remove_radius_servers();
for my $server (@server_keys) {
    if ( $servers{$server} ne 'deleted' ) {
        $all_deleted = 0;
        my $port    = $rconfig->returnValue("$server port");
        my $secret  = $rconfig->returnValue("$server secret");
        my $timeout = $rconfig->returnValue("$server timeout");
        $server_str .= "$server:$port\t$secret\t$timeout\n";
    }
}

if ($all_deleted) {

    # all radius servers deleted
    exit 1 if ( !remove_pam_radius() );
}
else {
    exit 1 if ( !add_radius_servers($server_str) );
    exit 1 if ( !add_pam_radius() );
}

exit 0;

