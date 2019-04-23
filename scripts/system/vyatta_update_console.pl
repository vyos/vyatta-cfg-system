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

# Update console configuration in systemd and grub based on Vyatta configuration

use strict;
use warnings;

use lib "/opt/vyatta/share/perl5";
use Vyatta::Config;
use File::Compare;
use File::Copy;
use experimental 'smartmatch';

die "$0 expects no arguments\n" if (@ARGV);

# if file is unchanged, do nothing and return false
# otherwise update to new version
sub update {
    my ($old, $new) = @_;

    if (compare($old, $new) != 0) {
        move($new, $old)
            or die "Can't move $new to $old";
        return 1;
    } else {
        unlink($new);
        return;
    }
}

sub update_getty{
  my $directory = "/etc/systemd/system";
  my $config = new Vyatta::Config;
  $config->setLevel("system console device");
  my @ttys;

  foreach my $tty ($config->listNodes()) {
    push(@ttys, "serial-getty\@$tty.service");
  }

  opendir DIR, $directory or die "Couldn't open dir '$directory': $!";
  while (my $file = readdir(DIR)) {
  next unless ($file =~ /^serial-getty/);
    if ( not $file ~~ @ttys ) {
      system("systemctl stop $file");
      if (-e "$directory/getty.target.wants/$file") {
        unlink "$directory/getty.target.wants/$file"
            or die "Failed to remove file $file: $!\n";
      }
      if (-e "$directory/$file") {
      unlink "$directory/$file"
          or die "Failed to remove file $file: $!\n";
      }
      system("systemctl daemon-reload");
    }
  }
  closedir DIR;

  foreach my $tty ($config->listNodes()) {
    my $SGETTY = "/lib/systemd/system/serial-getty\@.service";
    my $TMPGETTY  = "/etc/systemd/system/serial-getty\@$tty.service";
    my $SYMGETTY  = "/etc/systemd/system/getty.target.wants/serial-getty\@$tty.service";

    open(my $sgetty, '<', $SGETTY)
        or die "Can't open $SGETTY: $!";

    open(my $tmp, '>', $TMPGETTY)
        or die "Can't open $TMPGETTY: $!";

    my $speed = $config->returnValue("$tty speed");
    if ($tty =~ /^hvc\d/) {
        $speed = 38400 unless $speed;
    } else {
        $speed = 115200 unless $speed;
    }

    while (<$sgetty>) {
       if (/^ExecStart=/) {
           $_ =~ s/115200,38400,9600/$speed/g;
       }
       print {$tmp} $_;
    }
    close $sgetty;
    close $tmp;
    symlink("$TMPGETTY","$SYMGETTY");
    system("systemctl daemon-reload");
    if ( system("systemctl status serial-getty\@$tty.service 2>&1 > /dev/null")) {
      system("systemctl start serial-getty\@$tty.service");
    } else {
      system("/bin/stty -F /dev/$tty $speed cstopb");
    }
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
    $speed = "115200" unless defined($speed);

    open(my $grub, '<', $GRUBCFG)
        or die "Can't open $GRUBCFG: $!";

    open(my $tmp, '>', $GRUBTMP)
        or die "Can't open $GRUBTMP: $!";

    while (<$grub>) {
        if (/^serial /) {
            print {$tmp} "serial --unit=0 --speed=$speed\n";
        } elsif (/^(.* console=ttyS0),[0-9]+(.*)$/) {
            print {$tmp} "$1,$speed$2\n";
        } else {
            print {$tmp} $_;
        }
    }
    close $grub;
    close $tmp;

    update($GRUBCFG, $GRUBTMP);
}

update_getty;
update_grub;

exit 0;
