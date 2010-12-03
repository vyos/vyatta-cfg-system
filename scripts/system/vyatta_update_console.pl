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
use warnings;

use lib "/opt/vyatta/share/perl5";
use Vyatta::Config;
use File::Compare;
use File::Copy;

die "$0 expects no arguments\n" if (@ARGV);

# if file is unchanged, do nothing and return false
# otherwise update to new version
sub update {
    my ($old, $new) = @_;

    if ( compare($old, $new) != 0) {
	move($new, $old)
	    or die "Can't move $new to $old";
	return 1;
    } else {
	unlink($new);
	return;
    }
}

my $INITTAB = "/etc/inittab";
my $TMPTAB  = "/tmp/inittab.$$";

sub update_inittab {
    open (my $inittab, '<', $INITTAB)
	or die "Can't open $INITTAB: $!";

    open (my $tmp, '>', $TMPTAB)
	or die "Can't open $TMPTAB: $!";

    # Clone original inittab but remove all references to serial lines
    print {$tmp} grep { ! /^T|^# Vyatta/ } <$inittab>;
    close $inittab;

    my $config = new Vyatta::Config;
    $config->setLevel("system console device");

    print {$tmp} "# Vyatta console configuration (do not modify)\n";

    my $id = 0;
    foreach my $tty ($config->listNodes()) {
	my $speed = $config->returnValue("$tty speed");
	$speed = 9600 unless $speed;

	printf {$tmp} "T%d:23:respawn:", $id;
	if ($config->exists("$tty modem")) {
	    printf {$tmp} "/sbin/mgetty -x0 -s %d %s\n", $speed, $tty;
	} else {
	    printf {$tmp} "/sbin/getty -L %s %d vt100\n", $tty, $speed;
	}

	# id field is limited to 4 characters
	if (++$id >= 1000) {
	    warn "Ignoring $tty only 1000 serial devices supported\n";
	    last;
	}
    }
    close $tmp;

    if (update($INITTAB, $TMPTAB)) {
	# This is same as telinit q - it tells init to re-examine inittab
	kill 1, 1;
    }
}

my $GRUBCFG = "/boot/grub/grub.cfg";
my $GRUBTMP = "/tmp/grub.cfg.$$";

# For existing serial line change speed (if necessary)
# Only applys to ttyS0
sub update_grub {
    return unless (-f $GRUBCFG);

    my $config = new Vyatta::Config;
    $config->setLevel("system console device");
    return unless $config->exists("ttyS0");

    my $speed = $config->returnValue("ttyS0 speed");
    $speed = "9600" unless defined($speed);

    open (my $grub, '<', $GRUBCFG)
	or die "Can't open $GRUBCFG: $!";

    open (my $tmp, '>', $GRUBTMP)
	or die "Can't open $GRUBTMP: $!";

    while (<$grub>) {
	if (/^serial / ) {
	    print {$tmp} "serial --unit=0 --speed=$speed\n";
	} elsif (/^(.* console=ttyS0),[0-9]+ (.*)$/) {
	    print {$tmp} "$1,$speed $2\n";
	} else {
	    print {$tmp} $_;
	}
    }
    close $grub;
    close $tmp;

    update($GRUBCFG, $GRUBTMP);
}

update_inittab;
update_grub;

exit 0;
