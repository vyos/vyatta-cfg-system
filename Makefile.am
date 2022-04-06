bin_sudo_usersdir = $(bindir)/sudo-users
curverdir = $(sysconfdir)/config-migrate/current
checkparamsonrebootdir = $(bindir)/sudo-users/check-params-on-reboot.d
initddir = /etc/init.d

bin_SCRIPTS =
sbin_SCRIPTS =
sysconf_DATA =
initd_SCRIPTS =
bin_sudo_users_SCRIPTS =
checkparamsonreboot_SCRIPTS =

bin_SCRIPTS += scripts/progress-indicator
bin_SCRIPTS += scripts/restricted-shell

bin_sudo_users_SCRIPTS += scripts/vyatta-tunnel-dhcp.pl
sbin_SCRIPTS += scripts/vyatta-update-tunnel.pl
sbin_SCRIPTS += scripts/vyatta-dhcp-helper.pl

sbin_SCRIPTS += scripts/check_file_in_config_dir
sbin_SCRIPTS += scripts/vyatta-grub-setup
sbin_SCRIPTS += scripts/standalone_root_pw_reset
sbin_SCRIPTS += scripts/system/vyatta_update_sysctl.pl
sbin_SCRIPTS += scripts/snmp/if-mib-alias
sbin_SCRIPTS += scripts/vyatta-interfaces.pl
sbin_SCRIPTS += scripts/vyatta-address
sbin_SCRIPTS += scripts/vyatta-tunnel-cleanup
sbin_SCRIPTS += scripts/vyatta-raid-event
sbin_SCRIPTS += scripts/install/install-get-partition
sbin_SCRIPTS += scripts/install/install-functions
sbin_SCRIPTS += scripts/install/install-image-new
sbin_SCRIPTS += scripts/install/install-image-existing
sbin_SCRIPTS += scripts/install/install-postinst-new
sbin_SCRIPTS += scripts/install/install-image
sbin_SCRIPTS += scripts/vyatta-dhcpv6-client.pl
sbin_SCRIPTS += scripts/vyos-persistpath

sysconf_DATA += sysconf/LICENSE
sysconf_DATA += sysconf/filecaps
sysconf_DATA += sysconf/netdevice

rsyslogdir = /etc/rsyslog.d

curver_DATA = cfg-version/vrrp@3
curver_DATA += cfg-version/system@22
curver_DATA += cfg-version/broadcast-relay@1
curver_DATA += cfg-version/mdns@1
curver_DATA += cfg-version/dhcp-server@6
curver_DATA += cfg-version/dhcp-relay@2
curver_DATA += cfg-version/ssh@2
curver_DATA += cfg-version/salt@1
curver_DATA += cfg-version/l2tp@4
curver_DATA += cfg-version/lldp@1
curver_DATA += cfg-version/pptp@2
curver_DATA += cfg-version/ntp@1
curver_DATA += cfg-version/webproxy@2
curver_DATA += cfg-version/interfaces@25
curver_DATA += cfg-version/dns-forwarding@3
curver_DATA += cfg-version/vyos-accel-ppp@2
curver_DATA += cfg-version/rpki@1
curver_DATA += cfg-version/snmp@2
curver_DATA += cfg-version/sstp@4
curver_DATA += cfg-version/pppoe-server@5
curver_DATA += cfg-version/ipoe-server@1
curver_DATA += cfg-version/dhcpv6-server@1
curver_DATA += cfg-version/nat@5
curver_DATA += cfg-version/nat66@1
curver_DATA += cfg-version/quagga@9
curver_DATA += cfg-version/vrf@3
curver_DATA += cfg-version/isis@1
curver_DATA += cfg-version/bgp@2
curver_DATA += cfg-version/ospf@1
curver_DATA += cfg-version/policy@2
curver_DATA += cfg-version/conntrack@3
curver_DATA += cfg-version/conntrack-sync@2
curver_DATA += cfg-version/ipsec@9
curver_DATA += cfg-version/openconnect@1
curver_DATA += cfg-version/https@3
curver_DATA += cfg-version/flow-accounting@1
curver_DATA += cfg-version/firewall@7

cpiop = find  . ! -regex '\(.*~\|.*\.bak\|.*\.swp\|.*\#.*\#\)' -print0 | \
  cpio -0pd

install-exec-hook:
