#!/usr/bin/perl

use strict;

my $file = "messages";
my $log_file = "/var/log/messages";
if ($#ARGV == 3) {
  $file = shift;
  $log_file = "/var/log/user/$file";
}
my $files = shift;
my $size = shift;
my $set = shift;
my $log_conf = "/etc/logrotate.d/$file";

if (!defined($files) || !defined($size) || !defined($set)) {
  exit 1;
}

if (!($files =~ m/^\d+$/) || !($size =~ m/^\d+$/)) {
  exit 2;
}

# just remove it and make a new one below
# (the detection mechanism in XORP doesn't work anyway)
unlink $log_conf;

open(OUT, ">>$log_conf") or exit 3;
if ($set == 1) {
  print OUT <<EOF;
$log_file {
  missingok
  notifempty
  rotate $files
  size=${size}k
  postrotate
  kill -HUP `cat /var/run/syslogd.pid`
  endscript
}
EOF
}
close OUT;

sleep 1;
if (system("/usr/sbin/invoke-rc.d sysklogd restart")) {
  exit 4;
}

exit 0;

