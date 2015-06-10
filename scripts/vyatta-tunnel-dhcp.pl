#!/usr/bin/perl
use Getopt::Long;
use strict;

my ($iface, $dhcp, $tunnel, $nip, $oip, $reason);
GetOptions("interface=s"    => \$iface,
           "dhcp=s"         => \$dhcp,
           "tunnel=s"       => \$tunnel,
           "new_ip=s"       => \$nip,
           "old_ip=s"       => \$oip,
           "reason=s"       => \$reason);

# check if an update is needed
if (($reason eq "BOUND") || ($reason eq "REBOOT")) {
    $oip = "";
}
exit(0) if (($iface ne $dhcp) || ($oip eq $nip));
logger("DHCP address on $iface updated to $nip from $oip: Updating tunnel $tunnel configuration.");
system("sudo ip tunnel change $tunnel local $nip");

sub logger {
  my $msg = pop(@_);
  my $FACILITY = "daemon";
  my $LEVEL = "notice";
  my $TAG = "tunnel-dhclient-hook";
  my $LOGCMD = "logger -t $TAG -p $FACILITY.$LEVEL";
  system("$LOGCMD $msg");
}
