#!/usr/bin/perl

use strict;
my $SYSLOG_CONF = '/etc/syslog.conf';

my $match1 = shift;
my $match2 = shift;
my $update_line = shift;

if (!defined($match1) || !defined($match2) || !defined($update_line)) {
  exit 1;
}

if (system("touch $SYSLOG_CONF")) {
  exit 2;
}

my $exp1 = "";
my $exp2 = "";
if ($match1 ne "") {
  $exp1 = $match1;
  if ($match2 ne "") {
    $exp2 = $match2;
  }
} elsif ($match2 ne "") {
  $exp1 = $match2;
}

if ($exp2 ne "") {
  if (system("sed -i '/$exp1/{/$exp2/d}' $SYSLOG_CONF")) {
    exit 2;
  }
} elsif ($exp1 ne "") {
  if (system("sed -i '/$exp1/d' $SYSLOG_CONF")) {
    exit 3;
  }
}

open(OUT, ">>$SYSLOG_CONF") or exit 4;
if ($update_line ne "") {
  print OUT "$update_line";
}
close OUT;

sleep 1;
if (system("/usr/sbin/invoke-rc.d sysklogd restart")) {
  exit 5;
}

exit 0;

