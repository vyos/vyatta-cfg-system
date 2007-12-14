cfgdir = $(datadir)/vyatta-cfg/templates
share_perl5dir = $(datarootdir)/perl5
libudevdir = /lib/udev
etcudevdir = /etc/udev

bin_SCRIPTS =
sbin_SCRIPTS =
sysconf_DATA =

bin_SCRIPTS += scripts/progress-indicator
bin_SCRIPTS += scripts/vyatta-functions
bin_SCRIPTS += scripts/init-floppy
sbin_SCRIPTS += scripts/rl-system.init
sbin_SCRIPTS += scripts/install-system
sbin_SCRIPTS += scripts/quick-install
sbin_SCRIPTS += scripts/standalone_root_pw_reset
sbin_SCRIPTS += scripts/system/vyatta_update_login_user.pl
sbin_SCRIPTS += scripts/system/vyatta_update_logrotate.pl
sbin_SCRIPTS += scripts/system/vyatta_update_syslog.pl
sbin_SCRIPTS += scripts/snmp/vyatta-snmp.pl
sbin_SCRIPTS += scripts/snmp/snmpd.init
sbin_SCRIPTS += scripts/keepalived/vyatta-keepalived.pl
sbin_SCRIPTS += scripts/keepalived/vyatta-vrrp-state.pl
sbin_SCRIPTS += scripts/keepalived/vyatta-show-vrrp.pl
sbin_SCRIPTS += scripts/telnetd.init

share_perl5_DATA = scripts/keepalived/VyattaKeepalived.pm

sysconf_DATA += sysconf/logrotate_messages
sysconf_DATA += sysconf/motd.tail
sysconf_DATA += sysconf/syslog.conf
sysconf_DATA += sysconf/default_ssh
sysconf_DATA += sysconf/config.boot.default

libudev_SCRIPTS	 = scripts/vyatta_net_name
etcudev_DATA	 = sysconf/vyatta-net.rules

cpiop = find  . ! -regex '\(.*~\|.*\.bak\|.*\.swp\|.*\#.*\#\)' -print0 | \
  cpio -0pd

install-exec-hook:
	mkdir -p $(DESTDIR)$(cfgdir)
	cd templates; $(cpiop) $(DESTDIR)$(cfgdir)

