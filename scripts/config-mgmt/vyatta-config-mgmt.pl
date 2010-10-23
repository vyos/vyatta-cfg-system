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
use Getopt::Long;
use URI;

my $commit_uri_script = '/opt/vyatta/sbin/vyatta-commit-push.pl';
my $link_name         = '/etc/commit/vyatta-commit-push.pl';

my $debug = 0;

#
# main
#
my ($action, $uri);

GetOptions("action=s"      => \$action,
           "uri=s"         => \$uri,
);

die "Error: no action"      if ! defined $action;

my ($cmd, $rc) = ('', 1);

if ($action eq 'add-uri') {
    print "add-uri\n" if $debug;
    my $config = new Vyatta::Config;
    $config->setLevel('system config-mgmt');
    my @uris = $config->returnValues('commit-uri');
    if (scalar(@uris) > 1 and ! -e $link_name) {
        print "add link\n" if $debug;
        $rc = system("ln -s $commit_uri_script $link_name");
        exit $rc;
    }
    exit 0;
}

if ($action eq 'del-uri') {
    print "del-uri\n" if $debug;
    my $config = new Vyatta::Config;
    $config->setLevel('system config-mgmt');
    my @uris = $config->returnValues('commit-uri');
    if (scalar(@uris) <= 0) {
        print "remove link\n" if $debug;
        $rc = system("rm -f $link_name");
        exit $rc;
    }
    exit 0;
}

if ($action eq 'valid-uri') {
    die "Error: no uri"      if ! defined $uri;
    print "valid-uri [$uri]\n" if $debug;
    my $u = URI->new($uri);
    exit 1 if ! defined $u;
    my $scheme = $u->scheme();
    my $auth   = $u->authority();
    my $path   = $u->path();
    
    exit 1 if ! defined $scheme or ! defined $path;
    if ($scheme eq 'tftp') {
    } elsif ($scheme eq 'ftp') {
    } elsif ($scheme eq 'scp') {
    } elsif ($scheme eq 'file') {
    } else {
        print "Unsupported URI scheme\n";
        exit 1;
    }
    exit 0;
}

exit $rc;

# end of file
