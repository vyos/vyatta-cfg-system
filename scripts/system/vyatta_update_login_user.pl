#!/usr/bin/perl

use strict;
use Fcntl;
use POSIX qw(:unistd_h);

# arg: login_name
# returns the next available uid if login_name doesn't exist.
# otherwise returns (undef, <passwd fields for login_name>).
sub next_uid_if_not_exist {
  my $login = shift;
  my $min_uid = 1000;
  my $max_uid = 60000;
  if (open(LOGIN_DEF, "/etc/login.defs")) {
    while (<LOGIN_DEF>) {
      if (m/^\s*UID_MIN\s+(\d+)/) {
        $min_uid = $1;
        next;
      }
      if (m/^\s*UID_MAX\s+(\d+)/) {
        $max_uid = $1;
        next;
      }
    }
    close LOGIN_DEF;
  }
  
  open(PASSWD, "/etc/passwd") or exit 1;
  while (<PASSWD>) {
    chomp;
    my @passwd_fields = split /:/;
    if ($passwd_fields[0] eq $login) {
      close PASSWD;
      return (undef, @passwd_fields);
    }
    if ($min_uid <= $passwd_fields[2]) {
      next if ($passwd_fields[2] > $max_uid);
      $min_uid = $passwd_fields[2] + 1;
      next;
    }
  }
  close PASSWD;
  exit 2 if ($min_uid > $max_uid);
  return ($min_uid);
}

# arg: login_name
# returns the corresponding line in shadow or undef if login_name doesn't
# exist.
sub get_shadow_line {
  my $login = shift;
  open(SHADOW, "/etc/shadow") or exit 3;
  while (<SHADOW>) {
    chomp;
    if (m/^$login:/) {
      close SHADOW;
      return $_;
    }
  }
  close SHADOW;
  return undef;
}

my $user = shift;
my $full = shift;
my $encrypted = shift;

# emulate lckpwdf(3).
# difference: we only try to lock it once (non-blocking). lckpwdf will block
# for up to 15 seconds waiting for the lock.
# note that the lock is released when file is closed (e.g., exit), so no need
# for explicit unlock.
my $flock = pack "ssa20", F_WRLCK, SEEK_SET, "\0";
sysopen(PWDLCK, "/etc/.pwd.lock", O_WRONLY | O_CREAT, 0600) or exit 3;
fcntl(PWDLCK, F_SETLK, $flock) or exit 3;

if ($user eq "-d") {
  $user = $full;
  exit 4 if (!defined($user));
  
  # check if user is using the system
  my @pslines = `ps -U $user -u $user u`;
  if ($#pslines != 0) {
    # user is using the system
    print STDERR "Delete failed: user \"$user\" is using the system\n";
    exit 4;
  }

  my $ret = system("sed -i '/^$user:/d' /etc/passwd");
  exit 5 if ($ret >> 8);
  $ret = system("sed -i '/^$user:/d' /etc/shadow");
  exit 6 if ($ret >> 8);
  $ret = system("rm -rf /home/$user");
  exit 7 if ($ret >> 8);
  exit 0;
}

exit 4 if (!defined($user) || !defined($full) || !defined($encrypted));

my $DEF_GROUP = "quagga";
my $DEF_SHELL = "/bin/bash";

open(GRP, "/etc/group") or exit 5;
my $def_gid = undef;
while (<GRP>) {
  my @group_fields = split /:/;
  if ($group_fields[0] eq $DEF_GROUP) {
    $def_gid = $group_fields[2];
    last;
  }
}
exit 6 if (!defined($def_gid));

my @vals = next_uid_if_not_exist($user);
my ($new_user, $passwd_line, $shadow_line) = (0, "", "");
if (defined($vals[0])) {
  # add new user
  $new_user = 1;
  $passwd_line = "$user:x:$vals[0]:${def_gid}:$full:/home/$user:$DEF_SHELL";
  my $sline = get_shadow_line($user);
  exit 7 if (defined($sline));
  my $seconds = `date +%s`;
  my $days = int($seconds / 3600 / 24);
  $shadow_line = "$user:$encrypted:$days:0:99999:7:::";
} else {
  # modify existing user
  shift @vals;
  $vals[4] = $full;
  $passwd_line = join(':', @vals);
  my $sline = get_shadow_line($user);
  exit 8 if (!defined($sline));
  @vals = split /:/, $sline;
  $vals[1] = $encrypted;
  for (my $padding = (9 - $#vals - 1); $padding > 0; $padding--) {
    push @vals, ''; 
  }
  $shadow_line = join(':', @vals);
}

my $ret = 0;
if (!$new_user) {
  $ret = system("sed -i '/^$user:/d' /etc/passwd");
  exit 9 if ($ret >> 8);
  $ret = system("sed -i '/^$user:/d' /etc/shadow");
  exit 10 if ($ret >> 8);
}

open(PASSWD, ">>/etc/passwd") or exit 11;
print PASSWD "$passwd_line\n";
close PASSWD;
open(SHADOW, ">>/etc/shadow") or exit 12;
print SHADOW "$shadow_line\n";
close SHADOW;

if (($new_user) && !(-e "/home/$user")) {
  if (-d "/etc/skel") {
    $ret = system("cp -a /etc/skel /home/$user");
    exit 13 if ($ret >> 8);
    $ret = system("chmod 755 /home/$user");
    exit 14 if ($ret >> 8);
    $ret = system("chown -R $user:$DEF_GROUP /home/$user");
    exit 15 if ($ret >> 8);
  } else {
    $ret = system("mkdir -p /home/$user");
    exit 16 if ($ret >> 8);
    $ret = system("chmod 755 /home/$user");
    exit 17 if ($ret >> 8);
  }
}

exit 0;

