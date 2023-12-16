bin_sudo_usersdir = $(bindir)/sudo-users
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

sbin_SCRIPTS += scripts/vyatta-grub-setup
sbin_SCRIPTS += scripts/snmp/if-mib-alias
sbin_SCRIPTS += scripts/vyatta-interfaces.pl
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

cpiop = find  . ! -regex '\(.*~\|.*\.bak\|.*\.swp\|.*\#.*\#\)' -print0 | \
  cpio -0pd

install-exec-hook:
