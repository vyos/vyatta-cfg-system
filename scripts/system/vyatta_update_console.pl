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
# **** End License ****

# Update console configuration in /etc/inittab and grub
# based on Vyatta configuration

use strict;
use lib "/opt/vyatta/share/perl5";
use Vyatta::Config;
use File::Compare;
use File::Copy;

die "$0 expects no arguments\n" if (@ARGV);

sub update {
    my ($inpath, $outpath) = @_;

    if ( compare($inpath, $outpath) != 0) {
	copy($outpath, $inpath)
	    or die "Can't copy $outpath to $inpath";
    }
    unlink($inpath);
}

sub update_inittab {
    my ($inpath, $outpath) = @_;

    open (my $inittab, '<', $inpath)
	or return;

    open (my $tmp, '>', $outpath)
	or die "Can't open $outpath: $!";

    # Clone original inittab but remove all references to serial lines
    print {$tmp} grep { ! /^T/ } <$inittab>;
    close $inittab;

    my $config = new Vyatta::Config;
    $config->setLevel("system console device");

    my $id = 0;
    foreach my $tty ($config->listNodes()) {
	my $speed = $config->returnValue("$tty speed");
	$speed = 9600 unless $speed;
	my $type = $config->returnValue("$tty type");
    
	print {$tmp} "T$id:23:respawn:";

	# Three cases modem, direct, and normal
	if ($type eq "modem") {
	    print {$tmp} "/sbin/mgetty -x0 -s";
	} else {
	    print {$tmp} "/sbin/getty";
	    print {$tmp} " -L" if ($type eq "direct");
	}
	print {$tmp} "$speed $tty\n";
	++$id;
    }
    close $tmp;

    update($inpath, $outpath);
}

# For existing serial line change speed (if necessary)
sub update_grub {
    my ($inpath, $outpath) = @_;

    my $config = new Vyatta::Config;
    $config->setlevel("system console device");
    return unless $config->exists("ttyS0");

    my $speed = $config->returnValue("ttyS0 speed");
    $speed = "9600" unless defined($speed);

    open (my $grub, '<', $inpath)
	or die "Can't open $inpath: $!";
    open (my $tmp, '>', $outpath)
	or die "Can't open $outpath: $!";

    select $tmp;
    while (<$grub>) {
	if (/^serial / ) {
	    print "serial --unit=0 --speed=$speed\n";
	} elsif (/^(.* console=ttyS0),[0-9]+ (.*)$/) {
	    print "$1,$speed $2\n";
	} else {
	    print $_;
	}
    }
    close $grub;
    close $tmp;
    select STDOUT;

    update($inpath, $outpath);
}

my $INITTAB = "/etc/inittab";
my $TMPTAB  = "/tmp/inittab.$$";
my $GRUBCFG = "/boot/grub/grub.cfg";
my $GRUBTMP = "/tmp/grub.cfg.$$";

update_inittab($INITTAB, $TMPTAB);

update_grub($GRUBCFG, $GRUBTMP);

exit 0;
