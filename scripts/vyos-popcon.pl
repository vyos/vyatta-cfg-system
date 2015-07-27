#!/usr/bin/env perl
#
# Module: vyos-popcon.pl
# Sends anonymous system information to a server
#
# Copyright (C) 2015 VyOS maintainers and contributors
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 2 as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.


use lib "/opt/vyatta/share/perl5/";

use strict;
use warnings;
use File::Slurp;
use JSON::Any;
use LWP::UserAgent;
use Vyatta::Config;

use Data::Dumper;

my %data = ();
my $config = new Vyatta::Config();
my $json = new JSON::Any();

my $uuid_file = "/config/auth/popcon.uuid";
my $version_file = "/opt/vyatta/etc/version";

my $url = "http://popcon.vyos.net/submit";

sub send_to {
    my $data = shift;

    my $ua = LWP::UserAgent->new;
    $ua->agent("VyOS/popcon");

    my $req = HTTP::Request->new(POST => $url);
    $req->content_type('application/json');
    $req->content($data);

    my $res = $ua->request($req);

    if ($res->is_success) {
        print $res->content;
    }
    else {
        print $res->status_line, "\n";
    }
}

sub get_system_id
{
    my $uuid = read_file($uuid_file);
    $uuid =~ s/(.*)\s/$1/;
    return $uuid;
}

sub get_version
{
    my $contents = read_file($version_file);
    my ($version) = $contents =~ /Version\:\s*VyOS\s+(.*)\s/;
    return $version;
}

sub get_arch 
{
    my $arch = `uname -m`;
    $arch =~ s/(.*)\s/$1/;
    return $arch;
}

sub get_cpus
{
    my $output = `lscpu`;
    my ($cpus) = $output =~ /CPU\(s\)\:\s+(.*)\s/;
    return $cpus;
}

sub get_ram
{
    my $output = read_file('/proc/meminfo');
    my ($ram) = $output =~ /MemTotal:\s+(\d+)\s/;
    $ram = int($ram / 1024); # megabytes
    return $ram;
}

sub get_features
{
    my @features = ();
    push(@features, "bgp") if $config->exists("protocols bgp");
    push(@features, "ospf") if $config->exists("protocols ospf");
    push(@features, "ospfv3") if $config->exists("protocols ospfv3");
    push(@features, "rip") if $config->exists("protocols rip");
    push(@features, "ripng") if $config->exists("protocols ripng");
    push(@features, "nat") if $config->exists("nat");
    push(@features, "webproxy") if $config->exists("service webproxy");
    push(@features, "url-filtering") if $config->exists("service webproxy url-filtering");
    push(@features, "dns-forwarding") if $config->exists("service dns forwarding");
    push(@features, "dhcp-server") if $config->exists("service dhcp-server");
    push(@features, "dhcp-relay") if $config->exists("service dhcp-relay");
    push(@features, "dhcpv6-server") if $config->exists("service dhcpv6-server");
    push(@features, "dhcpv6-relay") if $config->exists("service dhcpv6-relay");
    push(@features, "netflow") if $config->exists("system flow-accounting netflow");
    push(@features, "sflow") if $config->exists("system flow-accounting sflow");
    push(@features, "snmp") if $config->exists("service snmp");
    push(@features, "lldp") if $config->exists("service lldp");
    push(@features, "telnet") if $config->exists("service telnet");
    push(@features, "pppoe-server") if $config->exists("service pppoe-server");
    push(@features, "ipsec") if $config->exists("vpn ipsec site-to-site");
    push(@features, "dmvpn") if ($config->exists("vpn ipsec profile") && $config->exists("protocols nhrp"));
    push(@features, "l2tp") if $config->exists("vpn l2tp remote-access");
    push(@features, "pptp") if $config->exists("vpn pptp remote-access");
    push(@features, "l2tpv3") if $config->exists("interfaces l2tpv3");
    push(@features, "openvpn") if $config->exists("interfaces openvpn");
    push(@features, "vxlan") if $config->exists("interfaces vxlan");
    push(@features, "vti") if $config->exists("interfaces vti");
    push(@features, "qos") if $config->exists("traffic-policy");
    push(@features, "bonding") if $config->exists("interfaces bonding");
    push(@features, "bridge") if $config->exists("interfaces bridge");
    push(@features, "tunnel") if $config->exists("interfaces tunnel");
    push(@features, "cluster") if $config->exists("cluster");
    push(@features, "load-balancing") if $config->exists("load-balancing wan");
    push(@features, "firewall") if $config->exists("firewall name");
    push(@features, "ipv6-firewall") if $config->exists("firewall ipv6-name");
    push(@features, "zone") if $config->exists("zone-policy");

    return (join ",", @features); 
}

if (! -f $uuid_file)
{
    # Generate the UUID file if it's missing
    system("uuid > $uuid_file");
}

# Prepare the data
$data{"uuid"} = get_system_id();
$data{"version"} = get_version();
$data{"arch"} = get_arch();
$data{"cpus"} = get_cpus();
$data{"ram"} = get_ram();
$data{"features"} = get_features();

send_to($json->objToJson(\%data));

