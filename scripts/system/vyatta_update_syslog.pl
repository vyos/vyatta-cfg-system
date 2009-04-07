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

# Update /etc/syslog.conf
# Exit code: 0 - update
#            1 - no change or error

use strict;
use lib "/opt/vyatta/share/perl5";
use Vyatta::Config;
use File::Compare;

my $SYSLOG_CONF = '/etc/syslog.conf';
my $SYSLOG_TMP  = "/tmp/syslog.conf.$$";
my $MESSAGES    = '/var/log/messages';
my $CONSOLE     = '/dev/console';
my %entries     = ();

die "$0 expects no arguments\n" if (@ARGV);
die "Must be run as root!\n" if ($EUID != 0);

# This builds a data structure that maps from target
# to selector list for that target
sub add_entries {
    my ( $config, $level, $target ) = @_;

    foreach my $facility ( $config->listNodes("$level facility") ) {
        my $loglevel = $config->returnValue("$level facility $facility level");
        $facility = '*' if ( $facility eq 'all' );
        $loglevel = '*' if ( $loglevel eq 'all' );

        $entries{$target} = [] unless $entries{$target};
        push @{ $entries{$target} }, $facility . '.' . $loglevel;
    }
}

my $config = new Vyatta::Config;
$config->setLevel("system syslog");

add_entries( $config, 'global', $MESSAGES );

# Default syslog.conf if no global entry
%entries = ( $MESSAGES => { '*:notice', 'local7:*' } ) unless (%entries);

add_entries( $config, 'console', $CONSOLE );

foreach my $host ( $config->listNodes('host') ) {
    add_entries( $config, "host $host", "@$host" );
}

foreach my $file ( $config->listNodes('file') ) {
    add_entries( $config, "file $file", $file );
}

foreach my $user ( $config->listNodes('user') ) {
    add_entries( $config, 'user $user', $user );
}

open my $in, '<', $SYSLOG_CONF
  or die "Can't open $SYSLOG_CONF: $!";

open my $out, '>', $SYSLOG_TMP
  or die "Can't open $SYSLOG_TMP: $!";

while (<$in>) {
    chomp;
    next if /# VYATTA$/;
    print {$out} $_, "\n";
}
close $in;

foreach my $target ( keys %entries ) {
    print $out join( ';', @{ $entries{$target} } ), "\t$target # VYATTA\n";
}
close $out
  or die "Can't output $SYSLOG_TMP: $!";

# Don't need to do anything, save time on boot
if ( compare( $SYSLOG_CONF, $SYSLOG_TMP ) == 0 ) {
    unlink($SYSLOG_TMP);
    exit 1;
}

system("sudo cp $SYSLOG_TMP $SYSLOG_CONF") == 0
    or die "Can't copy $SYSLOG_TMP to $SYSLOG_CONF";

unlink($SYSLOG_TMP);
exit 0;
