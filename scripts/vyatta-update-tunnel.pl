#!/usr/bin/perl

use Getopt::Long;
use strict;
use lib "/opt/vyatta/share/perl5";
use Vyatta::Config;

my ($iface, $tunnel, $option);
GetOptions("interface=s"    => \$iface,
           "tunnel=s"       => \$tunnel,
           "option=s"       => \$option
           );
my $FILE_DHCP_HOOK = "/etc/dhcp/dhclient-exit-hooks.d/tunnel-$tunnel";
my $dhcp_hook = '';
if ($option eq 'create') {
    $dhcp_hook =<<EOS;
#!/bin/sh
/opt/vyatta/bin/sudo-users/vyatta-tunnel-dhcp.pl --interface=\"\$interface\"  --dhcp=\"$iface\" --tunnel=\"$tunnel\" --new_ip=\"\$new_ip_address\" --old_ip=\"\$old_ip_address\" --reason=\"\$reason\"
EOS
}

open my $dhcp_hook_file, '>', $FILE_DHCP_HOOK
    or die "cannot open $FILE_DHCP_HOOK";
print ${dhcp_hook_file} $dhcp_hook;
close $dhcp_hook_file;
exit 0;

