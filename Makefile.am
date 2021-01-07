cfgdir = $(datadir)/vyatta-cfg/templates
bin_sudo_usersdir = $(bindir)/sudo-users
curverdir = $(sysconfdir)/config-migrate/current
checkparamsonrebootdir = $(bindir)/sudo-users/check-params-on-reboot.d
initddir = /etc/init.d
modprobedir = /etc/modprobe.d
modprobe_DATA = etc/modprobe.d/no-copybreak.conf
share_perl5dir = $(datadir)/perl5

bin_SCRIPTS =
sbin_SCRIPTS =
sysconf_DATA =
initd_SCRIPTS =
bin_sudo_users_SCRIPTS =
checkparamsonreboot_SCRIPTS =

checkparamsonreboot_DATA =
checkparamsonreboot_DATA += scripts/check-params-on-reboot.d/README

initd_SCRIPTS += etc/init.d/vyatta-config-reboot-params
checkparamsonreboot_SCRIPTS += scripts/check-params-on-reboot.d/ipv6_disable_blacklist

bin_SCRIPTS += scripts/progress-indicator

bin_sudo_users_SCRIPTS += scripts/vyatta-tunnel-dhcp.pl
sbin_SCRIPTS += scripts/vyatta-update-tunnel.pl
sbin_SCRIPTS += scripts/vyatta-dhcp-helper.pl

sbin_SCRIPTS += scripts/check_file_in_config_dir
sbin_SCRIPTS += scripts/rl-system.init
sbin_SCRIPTS += scripts/vyatta-grub-setup
sbin_SCRIPTS += scripts/standalone_root_pw_reset
sbin_SCRIPTS += scripts/vyatta-passwd-sync
sbin_SCRIPTS += scripts/system/vyatta_interface_rescan
sbin_SCRIPTS += scripts/system/vyatta_update_sysctl.pl
sbin_SCRIPTS += scripts/snmp/if-mib-alias
sbin_SCRIPTS += scripts/vyatta-interfaces.pl
sbin_SCRIPTS += scripts/vyatta-address
sbin_SCRIPTS += scripts/vyatta-tunnel-cleanup
sbin_SCRIPTS += scripts/vyatta-raid-event
sbin_SCRIPTS += scripts/vyatta-load-user-key.pl
sbin_SCRIPTS += scripts/install/install-get-partition
sbin_SCRIPTS += scripts/install/install-functions
sbin_SCRIPTS += scripts/install/install-image-new
sbin_SCRIPTS += scripts/install/install-image-existing
sbin_SCRIPTS += scripts/install/install-postinst-new
sbin_SCRIPTS += scripts/install/install-image
sbin_SCRIPTS += scripts/vyatta-dhcpv6-client.pl
sbin_SCRIPTS += scripts/vyos-persistpath

sbin_PROGRAMS = src/valid_address
sbin_PROGRAMS += src/local_ip

share_perl5_DATA =
share_perl5_DATA += scripts/XorpConfigParser.pm

src_valid_address = src/valid_address.c
src_local_ip = src/local_ip.c

sysconf_DATA += sysconf/LICENSE
sysconf_DATA += sysconf/issue
sysconf_DATA += sysconf/issue.net
sysconf_DATA += sysconf/motd.tail
sysconf_DATA += sysconf/rsyslog.conf
sysconf_DATA += sysconf/ntp.conf
sysconf_DATA += sysconf/default_ssh
sysconf_DATA += sysconf/securetty
sysconf_DATA += sysconf/vyatta-sysctl.conf
sysconf_DATA += sysconf/level
sysconf_DATA += sysconf/filecaps
sysconf_DATA += sysconf/capability.conf
sysconf_DATA += sysconf/cpufrequtils
sysconf_DATA += sysconf/sudoers
sysconf_DATA += sysconf/netdevice

libudevdir = /lib/udev
udevrulesdir = /lib/udev/rules.d
libudev_SCRIPTS	 = scripts/vyatta_net_name
udevrules_DATA = sysconf/65-vyatta-net.rules
udevrules_DATA += sysconf/42-qemu-usb.rules
udevrules_DATA += sysconf/64-vyos-vmware-net.rules
udevrules_DATA += sysconf/63-hyperv-vf-net.rules

cronhourlydir = /etc/cron.hourly
cronhourly_SCRIPTS = sysconf/vyatta-logrotate-hourly

rsyslogdir = /etc/rsyslog.d
#rsyslog_DATA = sysconf/vyatta-log.conf

curver_DATA = cfg-version/vrrp@2
curver_DATA += cfg-version/system@20
curver_DATA += cfg-version/broadcast-relay@1
curver_DATA += cfg-version/mdns@1
curver_DATA += cfg-version/dhcp-server@5
curver_DATA += cfg-version/dhcp-relay@2
curver_DATA += cfg-version/ssh@2
curver_DATA += cfg-version/salt@1
curver_DATA += cfg-version/l2tp@3
curver_DATA += cfg-version/lldp@1
curver_DATA += cfg-version/pptp@2
curver_DATA += cfg-version/ntp@1
curver_DATA += cfg-version/webproxy@2
curver_DATA += cfg-version/interfaces@18
curver_DATA += cfg-version/dns-forwarding@3
curver_DATA += cfg-version/vyos-accel-ppp@2
curver_DATA += cfg-version/snmp@2
curver_DATA += cfg-version/sstp@3
curver_DATA += cfg-version/pppoe-server@5
curver_DATA += cfg-version/ipoe-server@1
curver_DATA += cfg-version/dhcpv6-server@1
curver_DATA += cfg-version/nat@5

cpiop = find  . ! -regex '\(.*~\|.*\.bak\|.*\.swp\|.*\#.*\#\)' -print0 | \
  cpio -0pd

install-exec-hook:
	mkdir -p $(DESTDIR)$(cfgdir)
	cd templates; $(cpiop) $(DESTDIR)$(cfgdir)
