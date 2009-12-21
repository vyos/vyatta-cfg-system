#! /usr/bin/perl

# Standalone test for Vyatta::Interface, not intended to be used
# directly


use strict;
use warnings;
use Vyatta::Interface;
use Vyatta::Misc;

my @interfaces = getInterfaces();
print "Interfaces: ", join(' ',@interfaces),"\n";

print "IP\n";
foreach my $type (qw/all broadcast multicast pointtopoint loopback/) {
    print "\t$type = ";
    foreach my $addr (Vyatta::Misc::getInterfacesIPadresses($type)) {
	print $addr, '(', is_ip_v4_or_v6($addr), ') ';
    }
    print "\n";
}


foreach my $arg (@interfaces) {
    print "$arg : ";
    my $intf = new Vyatta::Interface($arg);

    if (! $intf) {
	print "undefined\n";
	next;
    }
    
    my $vif = $intf->vif();
    print "vif=$vif " if $vif;
    printf "path = '%s'\ndevice=%s\n", $intf->path(), $intf->physicalDevice();

    my @addresses = $intf->address();
    if ($#addresses eq -1) {
	print "address is no set\n";
    } else {
	print "address ", join(' ',@addresses), "\n";
    }

    foreach my $attr (qw(exists configured disabled using_dhcp flags up running)) {
	my $val = $intf->$attr();
	print " $attr=$val" if ($val);
    }
    print "\n";
}

exit 0;
