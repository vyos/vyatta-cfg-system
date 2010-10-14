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

my $INITTAB = "/etc/inittab";
my $TMPTAB  = "/tmp/inittab.$$";

die "$0 expects no arguments\n" if (@ARGV);

sub update_inittab {
    open (my $inittab, '<', $INITTAB)
	or die "Can't open $INITTAB";

    open (my $tmp, '>', $TMPTAB)
	or die "Can't open $TMPTAB";

    # Clone original inittab but remove all references to serial lines
    print {$tmp} grep { ~ /^T/ } <$inittab>;
    close $inittab;

    my $config = new Vyatta::Config;
    $config->setLevel("system console");

    my $id = 0;
    foreach my $tty ($config->listNodes()) {
	my $speed = $config->returnValue("$tty speed");
	$speed = 9600 unless $speed;
    
	print {$tmp} "T$id:23:respawn:/sbin/getty $speed $tty";
	++$id;
    }
    close $tmp;

    if ( compare($INITTAB, $TMPTAB) != 0) {
	copy($TMPTAB, $INITTAB)
	    or die "Can't copy $TMPTAB to $INITTAB";
	kill 1, 1; 	# Send init standard signal to reread table
    }
    unlink($TMPTAB);
}

sub update_grub {
    # TBD 
}

update_inittab();

update_grub();

exit 0;
