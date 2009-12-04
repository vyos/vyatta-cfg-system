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
# Portions created by Vyatta are Copyright (C) 2006, 2007 Vyatta, Inc.
# All Rights Reserved.
# 
# Author: Stephen Hemminger
# Date: 2009
# 
# **** End License ****

use strict;
use lib "/opt/vyatta/share/perl5/";

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
    my $rc = `curl -q -I $url 2>&1`;
    if ( $rc =~ /HTTP\/\d+\.?\d\s+(\d+)\s+(.*)$/mi ) {
	my $rc_code   = $1;
	my $rc_string = $2;

	die "http error: [$rc_code] $rc_string\n" 
	    unless ( $rc_code == 200 );
    } else {
	die "Error: $rc\n";
    }
}

sub load_url {
    my ($url, $tmpfile) = @_;
    my $proto;

    if ( $url =~ /^(\w+):\/\/\w/ ) {
        $proto = lc($1);
    } else {
	die "Invalid url [$url]\n";
    }

    die "Invalid url protocol [$proto]\n"
	unless( $proto eq 'tftp' ||
		$proto eq 'ftp'  ||
		$proto eq 'http' ||
		$proto eq 'scp' );

    check_http($url) 
	if ($proto eq 'http');

    system("curl -# -o $tmpfile $url") == 0
	or die "Can not fetch remote file $url\n";
}

usage unless ($#ARGV != 2);

my $user = $ARGV[0];
my $loadfile = $ARGV[1];

my $sbindir = $ENV{vyatta_sbindir};
my $config = new Vyatta::Config;
$config->setLevel("system login user");

die "$user does not exist in configuration\n"
    unless $config->exists($user);

if ( $loadfile =~ /^[^\/]\w+:\// ) {
    my $tmp_file = "/tmp/key.$user.$$";

    load_url ($loadfile, $tmp_file);
    $loadfile = $tmp_file;
}

open(my $cfg, '<', $loadfile)
    or die "Cannot open file $loadfile: $!\n";

while (<$cfg>) {
    chomp;
    # public key (format 2) consist of:
    # options, keytype, base64-encoded key, comment.
    # The options field is optional (but not supported).
    my ($keytype, $keycode, $comment) = split / /;
    die "Not a valid key file format (see man sshd)"
	unless defined($keytype) && defined($keycode) && defined($comment);

    die "$keytype: not a known ssh public format\n"
	unless ($keytype =~ /ssh-rsa|ssh-dsa/);

    my $cmd = "set system login user $user authentication public-keys $comment";
    system ("$sbindir/my_$cmd" . " key $keycode");
    die "\"$cmd\" key failed\n" 
	if ($? >> 8);

    system ("$sbindir/my_$cmd" . " type $keytype");
    die "\"$cmd\" type failed\n" 
	if ($? >> 8);
}
close $cfg;

system("$sbindir/my_commit");
if ( $? >> 8 ) {
    print "Load failed (commit failed)\n";
    exit 1;
}

print "Done\n";
exit 0;

	







    
