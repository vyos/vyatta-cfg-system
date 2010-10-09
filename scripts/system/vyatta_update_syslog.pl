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

# Update /etc/rsyslog.d/vyatta-log.conf
# Exit code: 0 - update
#            1 - no change or error

use strict;
use lib "/opt/vyatta/share/perl5";
use Vyatta::Config;
use File::Compare;

my $SYSLOG_CONF  = '/etc/rsyslog.d/vyatta-log.conf';
my $SYSLOG_TMP   = "/tmp/rsyslog.conf.$$";
my $MESSAGES     = '-/var/log/messages';
my $CONSOLE      = '/dev/console';

my %entries = ();

die "$0 expects no arguments\n" if (@ARGV);

sub add_entry {
    my ( $selector, $target ) = @_;

    $entries{$target} = [] unless $entries{$target};
    push @{ $entries{$target} }, $selector;
}

# This allows overloading local values in CLI
my %facmap = (
    'all'       => '*',
    'protocols' => 'local7',
);

# This builds a data structure that maps from target
# to selector list for that target
sub read_config {
    my ( $config, $level, $target ) = @_;

    foreach my $facility ( $config->listNodes("$level facility") ) {
        my $loglevel = $config->returnValue("$level facility $facility level");
        $facility = $facmap{$facility} if ( $facmap{$facility} );
        $loglevel = '*' if ( $loglevel eq 'all' );

        add_entry( $facility . '.' . $loglevel, $target );
    }
}

my $config = new Vyatta::Config;
$config->setLevel("system syslog");

read_config( $config, 'global', $MESSAGES );

# Default syslog.conf if no global entry
unless (%entries) {
    add_entry( '*.notice', $MESSAGES );
    add_entry( 'local7.*', $MESSAGES );
}

read_config( $config, 'console', $CONSOLE );

foreach my $host ( $config->listNodes('host') ) {
    read_config( $config, "host $host", '@'. $host );
}

foreach my $file ( $config->listNodes('file') ) {
    read_config( $config, "file $file", '/var/log/user/' . $file );
}

foreach my $user ( $config->listNodes('user') ) {
    read_config( $config, 'user $user', $user );
}

open my $out, '>', $SYSLOG_TMP
  or die "Can't open $SYSLOG_TMP: $!";

foreach my $target ( keys %entries ) {
    print $out join( ';', @{ $entries{$target} } ), "\t$target\n";
}
close $out
  or die "Can't output $SYSLOG_TMP: $!";

# Don't need to do anything, save time on boot
if ( -e $SYSLOG_CONF && compare( $SYSLOG_CONF, $SYSLOG_TMP ) == 0 ) {
    unlink($SYSLOG_TMP);
    exit 1;
}

system("sudo cp $SYSLOG_TMP $SYSLOG_CONF") == 0
  or die "Can't copy $SYSLOG_TMP to $SYSLOG_CONF";

unlink($SYSLOG_TMP);
exit 0;
