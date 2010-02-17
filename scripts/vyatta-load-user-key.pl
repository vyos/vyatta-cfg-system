#! /usr/bin/perl

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
# Author: Stephen Hemminger
# Date: February 2010
#
# **** End License ****

use lib "/opt/vyatta/share/perl5/";
use strict;
use warnings;

use Vyatta::Config;

my $sbindir = $ENV{vyatta_sbindir};

sub usage {
    print "Usage: $0 user filename|url\n";
    exit 1;
}

sub check_http {
    my ($url) = @_;

    #
    # error codes are send back in html, so 1st try a header
    # and look for "HTTP/1.1 200 OK"
    #
    my $rc = `curl -s -q -I $url 2>&1`;
    if ( $rc =~ /HTTP\/\d+\.?\d\s+(\d+)\s+(.*)$/mi ) {
	my $rc_code   = $1;
	my $rc_string = $2;

	die "http error: [$rc_code] $rc_string\n"
	    unless ( $rc_code == 200 );
    } else {
	die "Error: $rc\n";
    }
}

sub geturl {
    my $url = shift;

    # Is it a local file?
    unless ($url =~ m#(^[^/]\w+)://# ) {
	open(my $in, '<', $url)
	    or die "Cannot open file $url: $!\n";
	return $in;
    }

    my $proto = $1;
    check_http($url)
	if ($proto eq 'http');

    my $cmd = "curl -#";

    # Handle user@host syntax which curl doesn't do
    if ($proto eq 'scp') {
	if ($url =~ m#scp://(\w+)@(.*)# ) {
	    $cmd .= " -u $1";
	    $url = "scp://$2";
	}
    }
    $cmd .= " $url";

    open (my $curl, "$cmd |" )
	or die "$cmd command failed: $!";

    return $curl;
}

sub badkey {
    die "Not a valid key file format (see man sshd)"
}

sub getkeys {
    my ($user, $in) = @_;

    while (<$in>) {
	chomp;

	next if /^#/;	    # ignore comments

	# public key (format 2) consist of:
	# options, keytype, base64-encoded key, comment.
	my $pos = index $_, "ssh-";
	badkey
	    unless ($pos >= 0);	# missing keytype

	my ($keytype, $keycode, $comment) = split / /, substr($_, $pos);

	badkey
	    unless defined($keytype) && defined($keycode) && defined($comment);

	badkey
	    unless ($keytype eq 'ssh-rsa' || $keytype eq 'ssh-dss');

	my $cmd
	    = "set system login user $user authentication public-keys $comment";

	system ("$sbindir/my_$cmd" . " type $keytype");
	die "\"$cmd\" type failed\n"
	    if ($? >> 8);

	system ("$sbindir/my_$cmd" . " key \"$keycode\"");
	die "\"$cmd\" key failed\n"
	    if ($? >> 8);
    }
}

usage unless ($#ARGV == 1);

my $user = $ARGV[0];
my $source = $ARGV[1];

my $config = new Vyatta::Config;
$config->setLevel("system login user");

die "User $user does not exist in current configuration\n"
    unless $config->exists($user);

addkeys($user, geturl($source));

system("$sbindir/my_commit");
if ( $? >> 8 ) {
    print "Load failed (commit failed)\n";
    exit 1;
}

print "Done\n";
exit 0;
