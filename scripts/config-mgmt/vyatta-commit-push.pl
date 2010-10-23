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
# A copy of the GNU General Public License is available as
# `/usr/share/common-licenses/GPL' in the Debian GNU/Linux distribution
# or on the World Wide Web at `http://www.gnu.org/copyleft/gpl.html'.
# You can also obtain it by writing to the Free Software Foundation,
# Free Software Foundation, Inc., 51 Franklin St, Fifth Floor, Boston,
# MA 02110-1301, USA.
#
# This code was originally developed by Vyatta, Inc.
# Portions created by Vyatta are Copyright (C) 2010 Vyatta, Inc.
# All Rights Reserved.
#
# Author: Stig Thormodsrud
# Date: October 2010
# Description: Script to push cofig.boot to one or more URIs
#
# **** End License ****
#

use strict;
use warnings;
use lib '/opt/vyatta/share/perl5/';

use Vyatta::Config;
use POSIX;
use File::Basename;
use URI;


my $debug = 0;

my $config = new Vyatta::Config;

$config->setLevel('system config-mgmt');

my @uris = $config->returnOrigValues('commit-uri');

if (scalar(@uris) < 1) {
    print "No URI's configured\n";
    exit 0;
}

my $upload_file = '/opt/vyatta/etc/config/config.boot';

my $timestamp = strftime("_%Y%m%d_%H%M%S", localtime);
my $same_file = basename($upload_file) . $timestamp;

print "Archiving config...\n";
foreach my $uri (@uris) {
    my $u      = URI->new($uri);
    my $scheme = $u->scheme();
    my $auth   = $u->authority();
    my $path   = $u->path();
    my ($host, $remote) = ('', '');
    if (defined $auth and $auth =~ /.*\@(.*)/) {
        $host = $1;
    } else {
        $host = $auth if defined $auth;
    }
    $remote .= "$scheme://$host";
    $remote .= "$path" if defined $path;

    print "  $remote ";
    my $cmd = "curl -s -T $upload_file $uri/$same_file";
    print "cmd [$cmd]\n" if $debug;
    my $rc = system($cmd);
    if ($rc eq 0) {
        print " OK\n";
    } else {
        print " failed\n";
    }
}

exit 0;
