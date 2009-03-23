cfgdir = $(datadir)/vyatta-cfg/templates
share_perl5dir = $(datarootdir)/perl5/Vyatta
libudevdir = /lib/udev
etcudevdir = /etc/udev
bin_sudo_usersdir = $(bindir)/sudo-users
curverdir = $(sysconfdir)/config-migrate/current
netplugupdir = /etc/netplug/linkup.d
netplugdowndir = /etc/netplug/linkdown.d

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
sbin_SCRIPTS += scripts/system/vyatta_update_users.pl
sbin_SCRIPTS += scripts/system/vyatta_update_radius.pl
sbin_SCRIPTS += scripts/system/vyatta_update_tacacs.pl
sbin_SCRIPTS += scripts/system/vyatta_update_logrotate.pl
sbin_SCRIPTS += scripts/system/vyatta_update_resolv.pl
sbin_SCRIPTS += scripts/system/vyatta_update_syslog.pl
sbin_SCRIPTS += scripts/snmp/vyatta-snmp.pl
sbin_SCRIPTS += scripts/snmp/snmpd.init
sbin_SCRIPTS += scripts/keepalived/vyatta-keepalived.pl
sbin_SCRIPTS += scripts/keepalived/vyatta-vrrp-state.pl
sbin_SCRIPTS += scripts/telnetd.init
sbin_SCRIPTS += scripts/add_bootfile_eth_hwid
sbin_SCRIPTS += scripts/mod_bootfile_eth_hwid
sbin_SCRIPTS += scripts/dns-forwarding/vyatta-dns-forwarding.pl
sbin_SCRIPTS += scripts/dynamic-dns/vyatta-dynamic-dns.pl
sbin_SCRIPTS += scripts/vyatta-system-nameservers
sbin_SCRIPTS += scripts/vyatta-bonding.pl
sbin_SCRIPTS += scripts/vyatta-raid-event
sbin_SCRIPTS += scripts/vyatta-update-arp-params

noinst_DATA = test_bootfile

share_perl5_DATA = lib/Vyatta/Keepalived.pm

bin_sudo_users_SCRIPTS  = scripts/keepalived/vyatta-clear-vrrp.pl
bin_sudo_users_SCRIPTS += scripts/keepalived/vyatta-show-vrrp.pl

sysconf_DATA += sysconf/LICENSE
sysconf_DATA += sysconf/logrotate_messages
sysconf_DATA += sysconf/motd.tail
sysconf_DATA += sysconf/syslog.conf
sysconf_DATA += sysconf/default_ssh
sysconf_DATA += sysconf/vyatta-sysctl.conf
sysconf_DATA += sysconf/blacklist.DSA-1024
sysconf_DATA += sysconf/blacklist.RSA-2048

libudev_SCRIPTS	 = scripts/vyatta_net_name
etcudev_DATA	 = sysconf/vyatta-net.rules

curver_DATA = cfg-version/vrrp@1

cpiop = find  . ! -regex '\(.*~\|.*\.bak\|.*\.swp\|.*\#.*\#\)' -print0 | \
  cpio -0pd

install-exec-hook:
	mkdir -p $(DESTDIR)$(cfgdir)
	cd templates; $(cpiop) $(DESTDIR)$(cfgdir)

