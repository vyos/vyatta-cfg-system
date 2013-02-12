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
use File::Basename;
use File::Compare;
use File::Temp qw/ tempfile /;

my $SYSLOG_CONF  = '/etc/rsyslog.d/vyatta-log.conf';
my $SYSLOG_TMPL  = "/tmp/rsyslog.conf.XXXXXX";
my $MESSAGES     = '/var/log/messages';
my $CONSOLE      = '/dev/console';
my $LOGROTATE_CFG_DIR = '/opt/vyatta/etc/logrotate';

my %entries = ();

die "$0 expects no arguments\n" if (@ARGV);

sub add_target_selector {
    my ( $selector, $target ) = @_;

    $entries{$target}{selector} = [] unless $entries{$target}{selector};
    push @{ $entries{$target}{selector} }, $selector;
}

sub set_target_param {
    my ( $config, $level, $target, $param ) = @_;
    my $path = "$level archive $param";

    if (! $config->exists($path)) {
        my @tmpl = $config->parseTmpl($path);
        $entries{$target}{$param} = $tmpl[2];
    } else {
        $entries{$target}{$param} = $config->returnValue($path);
    }
}

sub get_target_param {
    my ( $target, $param ) = @_;
    return $entries{$target}{$param};
}

# This allows overloading local values in CLI
my %facmap = (
    'all'       => '*',
    'protocols' => 'local7',
    'dataplane' => 'local6',
);

# This builds a data structure that maps from target
# to selector list for that target
sub read_config {
    my ( $config, $level, $target ) = @_;

    foreach my $facility ( $config->listNodes("$level facility") ) {
        my $loglevel = $config->returnValue("$level facility $facility level");
        $facility = $facmap{$facility} if ( $facmap{$facility} );
        $loglevel = '*' if ( $loglevel eq 'all' );

        $entries{$target} = {} unless $entries{$target};
        add_target_selector( $facility . '.' . $loglevel, $target );
    }

    # This is a file target so we set size and files
    if ($target =~ m:^/var/log/:) {
        set_target_param($config, $level, $target, 'size');
        set_target_param($config, $level, $target, 'files');
    }
}

sub print_outchannel {
    my ( $fh, $channel, $target, $size ) = @_;
    # Force outchannel size to be 1k more than logrotate config to guarantee rotation
    $size = ($size + 5) * 1024;
    print $fh "\$outchannel $channel,$target,$size,/usr/sbin/logrotate ${LOGROTATE_CFG_DIR}/$channel\n";
    print $fh join( ';', @{ $entries{$target}{selector} } ), " \$$channel\n";
}

my $config = new Vyatta::Config;
$config->setLevel("system syslog");

read_config( $config, 'global', $MESSAGES );

# Default syslog.conf if no global entry
unless (%entries) {
    add_target_selector( '*.notice', $MESSAGES );
    add_target_selector( 'local7.*', $MESSAGES );
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

my ($out, $tempname) = tempfile($SYSLOG_TMPL, UNLINK => 1)
  or die "Can't create temp file: $!";

my $files;
my $size;
foreach my $target ( keys %entries ) {
    if ($target eq $MESSAGES) {
        $size = get_target_param($target, 'size');
        $files = get_target_param($target, 'files');
        print_outchannel($out, 'global', $target, $size);
        system("sudo /opt/vyatta/sbin/vyatta_update_logrotate.pl $files $size 1") == 0
            or die "Can't genrate global log rotation config: $!";
    } elsif ($target =~ m:^/var/log/user/:) {
        my $file = basename($target);
        $size = get_target_param($target, 'size');
        $files = get_target_param($target, 'files');
        print_outchannel($out, 'file_' . $file, $target, $size);
        system("sudo /opt/vyatta/sbin/vyatta_update_logrotate.pl $file $files $size 1") == 0
            or die "Can't genrate global log rotation config: $!";
    } else {
        print $out join( ';', @{ $entries{$target}{selector} } ), "\t$target\n";
    }
}
close $out
  or die "Can't output $tempname: $!";

# Don't need to do anything, save time on boot
if ( -e $SYSLOG_CONF && compare( $SYSLOG_CONF, $tempname ) == 0 ) {
    unlink($tempname);
    exit 1;
}

system("sudo cp $tempname $SYSLOG_CONF") == 0
  or die "Can't copy $tempname to $SYSLOG_CONF: $!";

unlink($tempname);
exit 0;
