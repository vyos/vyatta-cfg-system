#!/usr/bin/perl

use Getopt::Long;
use strict;
use lib "/opt/vyatta/share/perl5";
use Vyatta::Misc;

my ($iface, $want);
GetOptions("interface=s"    => \$iface,
           "want=s"         => \$want);

# Return the current router address from an interface that is
# configured via dhcp. Return 127.0.0.1 for all errors.
# This address will be used for the next hop address for static routes.

sub get_dhcp_router {
    my $dhcp_iface = pop(@_);
    if (!Vyatta::Misc::is_dhcp_enabled($dhcp_iface,0)) {
        return "127.0.0.1";
    }
    my $lease = "/var/lib/dhcp/dhclient_${dhcp_iface}.lease";
    my $router = `grep new_routers= $lease | cut -d"'" -f2`;
    my @r = split(/,/, $router);
    $router = $r[0];
    # Make sure the result looks like a IP
    if ($router !~ /\d+\.\d+\.\d+\.\d+/) {
        return "127.0.0.1";
    }
    # Remove trailing newlines
    $router =~ s/\n$//;
    return $router;
}


# Return the current ipv4 address from an interface that is
# configured via dhcp. Return 127.0.0.1 for all errors.
# This address will be used for the local-ip for tunnels,

sub get_dhcp_addr {
    my $dhcp_iface = pop(@_);
    if (!Vyatta::Misc::is_dhcp_enabled($dhcp_iface,0)) {
        return "127.0.0.1";
    }
    my @dhcp_addr = Vyatta::Misc::getIP($dhcp_iface,4);
    my $addr = pop(@dhcp_addr);
    if (!defined($addr)) {
        return "127.0.0.1";
    }
    @dhcp_addr = split(/\//, $addr);
    $addr = $dhcp_addr[0];
    return $addr;
}


if ($want eq 'local') {
    print get_dhcp_addr($iface);
}
else {
    print get_dhcp_router($iface);
}
exit 0;

