#!/usr/bin/perl

# Exit code:
#   0 - success
#   1 - missing parameter
#   2 - invalid files or size parameters
#   3 - unable to write logrotate config

use strict;

my $cfg_dir = "/opt/vyatta/etc/logrotate";
my $file = "global";
my $log_file = "/var/log/messages";
my $log_conf = "${cfg_dir}/$file";
if ($#ARGV == 3) {
  $file = shift;
  $log_file = "/var/log/user/$file";
  $log_conf = "${cfg_dir}/file_$file";
}
my $files = shift;
my $size = shift;
my $set = shift;

if (!defined($files) || !defined($size) || !defined($set)) {
  exit 1;
}

if (!($files =~ m/^\d+$/) || !($size =~ m/^\d+$/)) {
  exit 2;
}

# just remove it and make a new one below
# (the detection mechanism in XORP doesn't work anyway)
unlink $log_conf;

open my $out, '>', $log_conf
    or exit 3;
if ($set == 1) {
  print $out <<EOF;
$log_file {
  missingok
  notifempty
  create
  rotate $files
  size=${size}k
}
EOF
}
close $out;

exit 0;
