cfgdir = $(datadir)/vyatta-cfg/templates
share_perl5dir = $(datarootdir)/perl5/Vyatta/Login
bin_sudo_usersdir = $(bindir)/sudo-users
curverdir = $(sysconfdir)/config-migrate/current
gentmpdir = generated-templates
checkparamsonrebootdir = $(bindir)/sudo-users/check-params-on-reboot.d
initddir = /etc/init.d
netplugupdir = /etc/netplug/linkup.d
netplugdowndir = /etc/netplug/linkdown.d
modprobedir = /etc/modprobe.d
modprobe_DATA = etc/modprobe.d/no-copybreak.conf

bin_SCRIPTS =
sbin_SCRIPTS =
sysconf_DATA =
initd_SCRIPTS =
checkparamsonreboot_SCRIPTS =

checkparamsonreboot_DATA =
checkparamsonreboot_DATA += scripts/check-params-on-reboot.d/README

initd_SCRIPTS += etc/init.d/ec2-fetch-ssh-public-key
initd_SCRIPTS += etc/init.d/vyatta-config-reboot-params
initd_SCRIPTS += etc/init.d/vyos-intfwatchd
checkparamsonreboot_SCRIPTS += scripts/check-params-on-reboot.d/ipv6_disable_blacklist


netplugup_SCRIPTS = scripts/netplug/linkup/dhclient
netplugdown_SCRIPTS = scripts/netplug/linkdown/dhclient

bin_SCRIPTS += scripts/progress-indicator
bin_SCRIPTS += scripts/vyatta-functions
bin_SCRIPTS += scripts/restricted-shell

sbin_SCRIPTS += scripts/check_file_in_config_dir
sbin_SCRIPTS += scripts/rl-system.init
sbin_SCRIPTS += scripts/install-system
sbin_SCRIPTS += scripts/vyatta-grub-setup
sbin_SCRIPTS += scripts/standalone_root_pw_reset
sbin_SCRIPTS += scripts/vyatta-passwd-sync
sbin_SCRIPTS += scripts/system/vyatta_check_username.pl
sbin_SCRIPTS += scripts/system/vyatta_check_snmp_name.pl
sbin_SCRIPTS += scripts/system/vyatta_check_domainname.pl
sbin_SCRIPTS += scripts/system/vyatta_interface_rescan
sbin_SCRIPTS += scripts/system/vyatta_update_hosts.pl
sbin_SCRIPTS += scripts/system/vyatta_update_login.pl
sbin_SCRIPTS += scripts/system/vyatta_update_logrotate.pl
sbin_SCRIPTS += scripts/system/vyatta_update_resolv.pl
sbin_SCRIPTS += scripts/system/vyatta_update_sysctl.pl
sbin_SCRIPTS += scripts/system/vyatta_update_syslog.pl
sbin_SCRIPTS += scripts/system/vyatta_update_console.pl
sbin_SCRIPTS += scripts/system/vyatta_update_ntp.pl
sbin_SCRIPTS += scripts/system/vyatta_update_telnet
sbin_SCRIPTS += scripts/system/irq-affinity.pl
sbin_SCRIPTS += scripts/snmp/vyatta-snmp.pl
sbin_SCRIPTS += scripts/snmp/vyatta-snmp-v3.pl
sbin_SCRIPTS += scripts/snmp/if-mib-alias
sbin_SCRIPTS += scripts/telnetd.init
sbin_SCRIPTS += scripts/dns-forwarding/vyatta-dns-forwarding.pl
sbin_SCRIPTS += scripts/dynamic-dns/vyatta-dynamic-dns.pl
sbin_SCRIPTS += scripts/vyatta-system-nameservers
sbin_SCRIPTS += scripts/vyatta-interfaces.pl
sbin_SCRIPTS += scripts/vyatta-address
sbin_SCRIPTS += scripts/vyatta-tunnel-cleanup
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
sbin_SCRIPTS += scripts/vyatta-bridge.pl
sbin_SCRIPTS += scripts/vyatta-bridgegroup-depedency.pl
sbin_SCRIPTS += scripts/vyatta-dhcpv6-client.pl
sbin_SCRIPTS += scripts/vyatta-update-grub.pl
sbin_SCRIPTS += scripts/vyos-intfwatchd
sbin_SCRIPTS += scripts/ec2-check.pl

sbin_PROGRAMS = src/valid_address
sbin_PROGRAMS += src/local_ip
sbin_PROGRAMS += src/hypervisor_vendor

src_valid_address = src/valid_address.c
src_local_ip = src/local_ip.c
src_hypervisor_vendor = src/hypervisor_vendor.c

share_perl5_DATA = lib/Vyatta/Login/User.pm
share_perl5_DATA += lib/Vyatta/Login/RadiusServer.pm

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
sysconf_DATA += sysconf/pam_radius.cfg
sysconf_DATA += sysconf/filecaps
sysconf_DATA += sysconf/capability.conf
sysconf_DATA += sysconf/cpufrequtils
sysconf_DATA += sysconf/sudoers
sysconf_DATA += sysconf/netdevice

libudevdir = /lib/udev
udevrulesdir = /lib/udev/rules.d
libudev_SCRIPTS	 = scripts/vyatta_net_name
udevrules_DATA = sysconf/65-vyatta-net.rules

cronhourlydir = /etc/cron.hourly
cronhourly_SCRIPTS = sysconf/vyatta-logrotate-hourly

rsyslogdir = /etc/rsyslog.d
rsyslog_DATA = sysconf/vyatta-log.conf

curver_DATA = cfg-version/vrrp@1
curver_DATA += cfg-version/system@6

cpiop = find  . ! -regex '\(.*~\|.*\.bak\|.*\.swp\|.*\#.*\#\)' -print0 | \
  cpio -0pd

all-local:
	rm -rf $(gentmpdir)
	./gen-interface-templates.pl $(gentmpdir)

clean-local:
	rm -rf $(gentmpdir)

install-exec-hook:
	mkdir -p $(DESTDIR)$(cfgdir)
	cd templates; $(cpiop) $(DESTDIR)$(cfgdir)
	cd $(gentmpdir); $(cpiop) $(DESTDIR)$(cfgdir)
