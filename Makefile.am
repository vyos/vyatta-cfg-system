cfgdir = $(datadir)/vyatta-cfg/templates
share_perl5dir = $(datarootdir)/perl5/Vyatta/Login
bin_sudo_usersdir = $(bindir)/sudo-users
curverdir = $(sysconfdir)/config-migrate/current
netplugupdir = /etc/netplug/linkup.d
netplugdowndir = /etc/netplug/linkdown.d
modprobedir = /etc/modprobe.d
modprobe_DATA = etc/modprobe.d/no-copybreak.conf

bin_SCRIPTS =
sbin_SCRIPTS =
sysconf_DATA =

netplugup_SCRIPTS = scripts/netplug/linkup/dhclient
netplugdown_SCRIPTS = scripts/netplug/linkdown/dhclient

bin_SCRIPTS += scripts/progress-indicator
bin_SCRIPTS += scripts/vyatta-functions

sbin_SCRIPTS += scripts/init-floppy
sbin_SCRIPTS += scripts/rl-system.init
sbin_SCRIPTS += scripts/install-system
sbin_SCRIPTS += scripts/vyatta-grub-setup
sbin_SCRIPTS += scripts/standalone_root_pw_reset
sbin_SCRIPTS += scripts/vyatta-passwd-sync
sbin_SCRIPTS += scripts/system/vyatta_check_username.pl
sbin_SCRIPTS += scripts/system/vyatta_interface_rescan
sbin_SCRIPTS += scripts/system/vyatta_update_login.pl
sbin_SCRIPTS += scripts/system/vyatta_update_logrotate.pl
sbin_SCRIPTS += scripts/system/vyatta_update_resolv.pl
sbin_SCRIPTS += scripts/system/vyatta_update_syslog.pl
sbin_SCRIPTS += scripts/system/vyatta_update_console.pl
sbin_SCRIPTS += scripts/system/vyatta_update_ntp.pl
sbin_SCRIPTS += scripts/system/vyatta_update_telnet
sbin_SCRIPTS += scripts/snmp/vyatta-snmp.pl
sbin_SCRIPTS += scripts/snmp/snmpd.init
sbin_SCRIPTS += scripts/keepalived/vyatta-keepalived.pl
sbin_SCRIPTS += scripts/keepalived/vyatta-vrrp-state.pl
sbin_SCRIPTS += scripts/telnetd.init
sbin_SCRIPTS += scripts/dns-forwarding/vyatta-dns-forwarding.pl
sbin_SCRIPTS += scripts/dynamic-dns/vyatta-dynamic-dns.pl
sbin_SCRIPTS += scripts/vyatta-system-nameservers
sbin_SCRIPTS += scripts/vyatta-interfaces.pl
sbin_SCRIPTS += scripts/check-ipv4-ipv6.pl
sbin_SCRIPTS += scripts/vyatta-bonding.pl
sbin_SCRIPTS += scripts/vyatta-raid-event
sbin_SCRIPTS += scripts/vyatta-update-arp-params
sbin_SCRIPTS += scripts/vyatta-banner.pl
sbin_SCRIPTS += scripts/vyatta-load-user-key.pl
sbin_SCRIPTS += scripts/install/install-get-partition
sbin_SCRIPTS += scripts/install/install-functions
sbin_SCRIPTS += scripts/install/install-image-new
sbin_SCRIPTS += scripts/install/install-image-existing
sbin_SCRIPTS += scripts/install/install-postinst-new
sbin_SCRIPTS += scripts/install/install-image
sbin_SCRIPTS += scripts/vyatta-bridgegroup-depedency.pl
sbin_SCRIPTS += scripts/vyatta-dhcpv6-client.pl
sbin_SCRIPTS += scripts/vyatta-update-grub.pl
sbin_SCRIPTS += scripts/config-mgmt/vyatta-commit-push.pl
sbin_SCRIPTS += scripts/config-mgmt/vyatta-config-mgmt.pl

share_perl5_DATA = lib/Vyatta/Login/User.pm
share_perl5_DATA += lib/Vyatta/Login/RadiusServer.pm

noinst_DATA = test_bootfile

bin_sudo_users_SCRIPTS  = scripts/keepalived/vyatta-clear-vrrp.pl
bin_sudo_users_SCRIPTS += scripts/keepalived/vyatta-show-vrrp.pl

sysconf_DATA += sysconf/LICENSE
sysconf_DATA += sysconf/logrotate_messages
sysconf_DATA += sysconf/issue
sysconf_DATA += sysconf/issue.net
sysconf_DATA += sysconf/motd.tail
sysconf_DATA += sysconf/rsyslog.conf
sysconf_DATA += sysconf/ntp.conf
sysconf_DATA += sysconf/default_ssh
sysconf_DATA += sysconf/securetty
sysconf_DATA += sysconf/vyatta-sysctl.conf
sysconf_DATA += sysconf/blacklist.DSA-1024
sysconf_DATA += sysconf/blacklist.RSA-2048
sysconf_DATA += sysconf/level
sysconf_DATA += sysconf/pam_radius.cfg
sysconf_DATA += sysconf/filecaps
sysconf_DATA += sysconf/capability.conf

libudevdir = /lib/udev
udevrulesdir = /lib/udev/rules.d
libudev_SCRIPTS	 = scripts/vyatta_net_name
udevrules_DATA = sysconf/65-vyatta-net.rules

rsyslogdir = /etc/rsyslog.d
rsyslog_DATA = sysconf/vyatta-log.conf

curver_DATA = cfg-version/vrrp@1
curver_DATA += cfg-version/system@4

cpiop = find  . ! -regex '\(.*~\|.*\.bak\|.*\.swp\|.*\#.*\#\)' -print0 | \
  cpio -0pd

install-exec-hook:
	mkdir -p $(DESTDIR)$(cfgdir)
	cd templates; $(cpiop) $(DESTDIR)$(cfgdir)
