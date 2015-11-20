#!/usr/bin/perl
#
# **** License ****
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 2 as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# This code was originally developed by Vyatta, Inc.
# Portions created by Vyatta are Copyright (C) 2013 Vyatta, Inc.
# All Rights Reserved.
#
# **** End License ****

use strict;
use warnings;

use lib "/opt/vyatta/share/perl5/";
use Vyatta::Config;
use File::Copy;
use Getopt::Long;
use Socket;
use Socket6;

my $snmp_v3_level      = 'service snmp v3';
my $snmp_init          = 'invoke-rc.d snmpd';
my $snmpd_conf         = '/etc/snmp/snmpd.conf';
my $snmpd_usr_conf     = '/usr/share/snmp/snmpd.conf';
my $snmpd_var_conf     = '/var/lib/snmp/snmpd.conf';
my $snmpd_conf_tmp     = "/tmp/snmpd.conf.$$";
my $snmpd_usr_conf_tmp = "/tmp/snmpd.usr.conf.$$";
my $snmpd_var_conf_tmp = "/tmp/snmpd.var.conf.$$";
my $versionfile        = '/opt/vyatta/etc/version';
my $local_agent        = 'unix:/var/run/snmpd.socket';

my $oldEngineID = "";
my $setserialno = "";

my %OIDs = (
    "md5",  ".1.3.6.1.6.3.10.1.1.2",
    "sha",  ".1.3.6.1.6.3.10.1.1.3",
    "aes",  ".1.3.6.1.6.3.10.1.2.4",
    "des",  ".1.3.6.1.6.3.10.1.2.2",
    "none", ".1.3.6.1.6.3.10.1.2.1"
);

# generate a random character hex string
sub randhex {
    my $length = shift;
    return join "", map {unpack "H*", chr(rand(256))} 1 .. ($length / 2);
}

sub snmpd_running {
    open(my $pidf, '<', "/var/run/snmpd.pid")
        or return;
    my $pid = <$pidf>;
    close $pidf;

    chomp $pid;
    my $exe = readlink "/proc/$pid/exe";

    return (defined($exe) && $exe eq "/usr/sbin/snmpd");
}

sub check_snmp_exit_code {
    my $code = shift;

    # snmpd can start/restart with exit code 256 if trap-target is unavailable
    if ($code != 0 && $code != 256) {
        return 1;
    }else {
        return 0;
    }
}

sub snmpd_stop {
    system("start-stop-daemon --stop --exec /usr/sbin/snmpd --oknodo -R 2 > /dev/null 2>&1");
    if (check_snmp_exit_code($?)) {
        print "ERROR: Can not stop snmpd!\n";
        exit(1);
    }
}

sub snmpd_start {
    system("$snmp_init start > /dev/null 2>&1");
    if (check_snmp_exit_code($?)) {
        print "ERROR: Can not start snmpd!\n";
        exit(1);
    }
}

sub snmpd_update {
    system("$snmp_init reload > /dev/null 2>&1");
    if (check_snmp_exit_code($?)) {
        print "ERROR: Can not reload snmpd!\n";
        exit(1);
    }
}

sub snmpd_restart {
    system("$snmp_init restart > /dev/null 2>&1");
    if (check_snmp_exit_code($?)) {
        print "ERROR: Can not restart snmpd!\n";
        exit(1);
    }
}

# get vyatta version
sub get_version {
    my $version = "unknown-version";

    if (open(my $f, '<', $versionfile)) {
        while (<$f>) {
            chomp;
            if (m/^Version\s*:\s*(.*)$/) {
                $version = $1;
                last;
            }
        }
        close $f;
    }
    return $version;
}

sub ipv6_disabled {
    socket(my $s, PF_INET6, SOCK_DGRAM, 0)
        or return 1;
    close($s);
    return;
}

# write tsm config from current to snmpd_conf
sub set_tsm {
    my $config = get_snmp_config();
    if ($config->exists("tsm")) {
        my $port      = $config->returnValue("tsm port");
        my $local_key = $config->returnValue("tsm local-key");
        system("sed -i 's/^agentaddress.*\$/&,tlstcp:$port,dtlsudp:$port/' $snmpd_conf_tmp");
        system("echo \"[snmp] localCert $local_key\" >> $snmpd_conf_tmp");
    }
}

# delete all SNMP config files
# can be called directly
sub snmp_delete {
    snmpd_stop();

    my @files = ($snmpd_conf, $snmpd_usr_conf, $snmpd_var_conf);
    foreach my $file (@files) {
        if (-e $file) {
            unlink($file);
        }
    }
}

sub get_snmp_config {
    my $config = new Vyatta::Config;
    $config->setLevel($snmp_v3_level);
    return $config;
}

# write views from vyatta config to snmpd_conf
sub set_views {
    print "# views \n";
    my $config = get_snmp_config();
    foreach my $view ($config->listNodes("view")) {
        foreach my $oid ($config->listNodes("view $view oid")) {
            my $mask = '';
            $mask = $config->returnValue("view $view oid $oid mask")
                if $config->exists("view $view oid $oid mask");
            if ($config->exists("view $view oid $oid exclude")) {
                print "view $view excluded .$oid $mask\n";
            }else {
                print "view $view included .$oid $mask\n";
            }
        }
    }
    print "\n";
}

# write groups from vyatta config to snmpd_conf
sub set_groups {
    print"#access\n#             context sec.model sec.level match  read    write  notif\n";
    my $config = get_snmp_config();
    foreach my $group ($config->listNodes("group")) {
        my $mode     = $config->returnValue("group $group mode");
        my $view     = $config->returnValue("group $group view");
        my $secLevel = $config->returnValue("group $group seclevel");
        if ($mode eq "ro") {
            print "access $group \"\" usm $secLevel exact $view none none\n";
            print "access $group \"\" tsm $secLevel exact $view none none\n";
        }else {
            print "access $group \"\" usm $secLevel exact $view $view none\n";
            print "access $group \"\" tsm $secLevel exact $view $view none\n";
        }
    }
    print "\n";
}

# write users from vyatta config to snmpd_conf
sub set_users_in_etc {

    print "#group\n";
    my $tsm_counter = 0;
    my $config      = get_snmp_config();
    foreach my $user ($config->listNodes("user")) {
        $config->setLevel($snmp_v3_level . " user $user");
        if ($config->exists("group")) {
            my $group = $config->returnValue("group");
            print "group $group usm $user\n";
            print "group $group tsm $user\n";
        }
        if ($config->exists("tsm-key")) {
            my $cert = $config->returnValue("tsm-key");
            $tsm_counter++;
            print "certSecName $tsm_counter $cert --sn $user\n";
        }
    }

    print "\n";
}

# write users from vyatta config to config files in /usr & /var
sub set_users_to_other {
    open(my $usr_conf, '>>', $snmpd_usr_conf_tmp)
        or die "Couldn't open $snmpd_usr_conf_tmp - $!";
    open(my $var_conf, '>>', $snmpd_var_conf_tmp)
        or die "Couldn't open $snmpd_var_conf_tmp - $!";

    print $var_conf "\n";

    my $config  = get_snmp_config();
    my $needTsm = 0;
    if ($config->exists("tsm")) {
        $needTsm = 1;
    }

    my %trap_users = ();

    foreach my $trap ($config->listNodes("trap-target")) {
        $trap_users{$config->returnValue("trap-target $trap user")} = 1;
    }

    foreach my $user ($config->listNodes("user")) {
        delete $trap_users{$user};
        $config->setLevel($snmp_v3_level . " user $user");
        my $auth_type = $config->returnValue("auth type");
        my $priv_type = $config->returnValue("privacy type");
        if ($config->exists("auth")) {
            if ($config->exists("auth plaintext-key")) {
                my $auth_key = $config->returnValue("auth plaintext-key");
                my $priv_key = '';
                $priv_key = $config->returnValue("privacy plaintext-key")
                    if $config->exists("privacy plaintext-key");
                print $var_conf "createUser $user \U$auth_type\E $auth_key \U$priv_type\E $priv_key\n";
            }else {
                my $name_print    = get_printable_name($user);
                my $EngineID      = $config->returnValue("engineid");
                if ($EngineID eq "") {
                    die "ERROR: engineid is null\n";
                }
                my $auth_type_oid = $OIDs{$auth_type};
                my $auth_key_hex  = $config->returnValue("auth encrypted-key");

                my ($priv_type_oid, $priv_key_hex);
                if ($config->exists("privacy")) {
                    $priv_type_oid = $OIDs{$priv_type};
                    $priv_key_hex =$config->returnValue("privacy encrypted-key");
                }else {
                    $priv_type_oid = $OIDs{'none'};
                    $priv_key_hex  = '0x';
                }
                print $var_conf "usmUser 1 3 $EngineID $name_print $name_print NULL $auth_type_oid $auth_key_hex $priv_type_oid $priv_key_hex 0x\n";
            }
        }
        my $mode = $config->returnValue("mode");
        my $end  = "auth";
        if ($config->exists("privacy")) {
            $end = "priv";
        }
        print $usr_conf $mode . "user $user $end\n";
        if ($needTsm) {
            print $usr_conf $mode . "user -s tsm $user $end\n";
        }
    }

    # add users for trap if they are not exists in vyatta config /services/snmp/v3/user
    foreach my $user (keys %trap_users) {
        my $name_print = get_printable_name($user);
        print $var_conf "usmUser 1 3 0x". randhex(26). " $name_print $name_print NULL .1.3.6.1.6.3.10.1.1.2 0x". randhex(32). " .1.3.6.1.6.3.10.1.2.1 0x 0x\n";
        print $usr_conf "rouser $user auth\n";
    }

    print $var_conf "setserialno $setserialno\n"
        if !($setserialno eq "");
    print $var_conf "oldEngineID $oldEngineID\n"
        if !($oldEngineID eq "");

    close $usr_conf;
    close $var_conf;
}

# if name contains '-' then it must be printed in hex format
sub get_printable_name {
    my $name = shift;
    if ($name =~ /-/) {
        my @array = unpack('C*', $name);
        my $stringHex = '0x';
        foreach my $c (@array) {
            $stringHex .= sprintf("%lx", $c);
        }
        return $stringHex;
    }else {
        return "\"$name\"";
    }
}

# read encrypted keys from config file in /var to vyatta config
# read additional info from config file in /var to VConfig variable
# delete plaintext passwords in vyatta config
sub update_users_vyatta_conf {
    open(my $var_conf, '<', $snmpd_var_conf)
        or die "Couldn't open $snmpd_usr_conf - $!";
    my $config = get_snmp_config();
    while (my $line = <$var_conf>) {
        if ($line =~ /^oldEngineID (.*)$/) {
            my $value = $1;
            if (  $config->exists("engineid")
                &&$config->returnValue("engineid") eq "")
            {
                system("/opt/vyatta/sbin/my_set service snmp v3 engineid $value > /dev/null");
            }
        }
        if ($line =~ /^usmUser /) {
            my @values = split(/ /, $line);
            my $name = $values[4];
            if ($name =~ /^"(.*)"$/) {
                $name = $1;
            }else {
                $name = pack('H*', $name);
            }

            # this file contain users for trap-target and vyatta... user
            # these users recreating automatically on each commit
            if ($config->exists("user $name")) {
                system("/opt/vyatta/sbin/my_set service snmp v3 user \"$name\" engineid $values[3] > /dev/null");
                system("/opt/vyatta/sbin/my_set service snmp v3 user \"$name\" auth encrypted-key $values[8] > /dev/null");
                if ($values[10] ne "\"\"" && $values[10] ne "0x") {
                    system("/opt/vyatta/sbin/my_set service snmp v3 user \"$name\" privacy encrypted-key $values[10] > /dev/null");
                    system("/opt/vyatta/sbin/my_delete service snmp v3 user \"$name\" privacy plaintext-key > /dev/null");
                }
                system("/opt/vyatta/sbin/my_delete service snmp v3 user \"$name\" auth plaintext-key > /dev/null");
            }
        }
    }
    close $var_conf;
}

# write trap-target hosts from vyatta config to snmpd_conf
sub set_hosts {
    print "#trap-target\n";
    my $config = get_snmp_config();
    foreach my $target ($config->listNodes("trap-target")) {
        $config->setLevel($snmp_v3_level . " trap-target $target");
        my $auth_key = '';
        if ($config->exists("auth plaintext-key")) {
            $auth_key = "-A " . $config->returnValue("auth plaintext-key");
        }else {
            $auth_key = "-3m " . $config->returnValue("auth encrypted-key");
        }
        my $auth_type   = $config->returnValue("auth type");
        my $user        = $config->returnValue("user");
        my $port        = $config->returnValue("port");
        my $protocol    = $config->returnValue("protocol");
        my $type        = $config->returnValue("type");
        my $inform_flag = '-Ci';
        $inform_flag = '-Ci' if ($type eq 'inform');

        if ($type eq 'trap') {
            $inform_flag = '-e ' . $config->returnValue("engineid");
        }
        my $privacy  = '';
        my $secLevel = 'authNoPriv';
        if ($config->exists("privacy")) {
            my $priv_key = '';
            if ($config->exists("privacy plaintext-key")) {
                $priv_key ="-X " . $config->returnValue("privacy plaintext-key");
            }else {
                $priv_key ="-3M " . $config->returnValue("privacy encrypted-key");
            }
            my $priv_type = $config->returnValue("privacy type");
            $privacy  = "-x $priv_type $priv_key";
            $secLevel = 'authPriv';
        }

        # TODO understand difference between master and local
        # Uses:
        # set -3m / -3M for auth / priv  for master
        # or -3k / -3K for local
        # Current use only master
        my $target_print = $target;
        if ($target =~ /:/) {
            $target_print = "[$target]";
            $protocol     = $protocol . "6";
        }
        print"trapsess -v 3 $inform_flag -u $user -l $secLevel -a $auth_type $auth_key $privacy $protocol:$target_print:$port\n";
    }
    print "\n";
}

# check changes in auth and privacy nodes
# deny set encrypted-key in case engineid wasn't set
sub check_user_auth_changes {
    my $config = get_snmp_config();
    my $v3engineid = "";

    if($config->exists("engineid")){
        $v3engineid=$config->returnValue("engineid");
    }

    if ($config->isChanged("user") || $config->isChanged("engineid")) {
        my $haveError = 0;
        foreach my $user ($config->listNodes("user")) {
            $config->setLevel($snmp_v3_level . " user $user");
            if (  $config->exists("engineid")
                &&!($v3engineid eq "")
                &&!($config->returnValue("engineid") eq "")
                &&!($config->returnValue("engineid") eq $v3engineid))
            {
                print"Warning: Encrypted key(s) for snmp v3 user \"$user\" was(were) generated for another SNMP engineid. It won't work. Please recreate this user.\n";
            }
            if ($config->exists("auth")) {
                if (
                    !(
                        $config->exists("engineid") &&($config->exists("auth encrypted-key")
                            ||$config->exists("privacy encrypted-key"))
                    )
                    )
                {
                    $haveError = 1;
                    print"Discard encrypted-key on user \"$user\". It's necessary to setup engineid the encrypted-key was generated with.\n";
                }
                my $isAuthKeyChanged = $config->isChanged("auth plaintext-key");
                my $isAuthEKeyChanged = $config->isChanged("auth encrypted-key");
                if ($config->exists("privacy")) {
                    my $isPrivKeyChanged =$config->isChanged("privacy plaintext-key");
                    my $isPrivEKeyChanged =$config->isChanged("privacy encrypted-key");
                    if (   ($isPrivEKeyChanged && !$isAuthEKeyChanged)
                        || ($isPrivKeyChanged && !$isAuthKeyChanged))
                    {
                        $haveError = 1;
                        print"Please, set correct auth and privacy for user \"$user\"\n";
                        print"Set plaintext-key for auth and privacy or set encrypted-key for both\n";
                    }
                }
            }else {
                if ($config->exists("privacy")) {
                    $haveError = 1;
                    print "Please, delete privacy for user \"$user\"\n";
                }
            }
        }
        if ($haveError) {
            exit(1);
        }
    }
}

# check relation between user & group & view
sub check_relation {
    my $config    = get_snmp_config();
    my $haveError = 0;
    foreach my $user ($config->listNodes("user")) {
        if ($config->exists("user $user group")) {
            my $group = $config->returnValue("user $user group");
            if (!$config->exists("group $group")) {
                $haveError = 1;
                print"Please, create group \"$group\". It's need for user \"$user\"\n";
            }
        }
    }
    foreach my $group ($config->listNodes("group")) {
        my $view = $config->returnValue("group $group view");
        if (!$config->exists("view $view")) {
            $haveError = 1;
            print"Please, create view \"$view\". It's need for group \"$group\"\n";
        }
    }
    if ($haveError) {
        exit(1);
    }
}

# check is new tsm port free on system
sub check_tsm_port {
    my $config = get_snmp_config();
    if ($config->isChanged("tsm port")) {
        my $port   = $config->returnValue("tsm port");
        my $reg    = ":$port\$";
        my $output = `netstat -anltup | awk '{print  \$4}'`;
        foreach my $line (split(/\n/, $output)) {
            if ($line =~ /$reg/) {
                print"Actually port $port is using. It can not be used for tsm.\n";
                exit(1);
            }
        }
    }
}

# check group seclevel and user auth/privacy
sub check_seclevel {
    my $config    = get_snmp_config();
    my $haveError = 0;
    if ($config->isChanged("user") || $config->isChanged("group")) {
        foreach my $user ($config->listNodes("user")) {
            if ($config->exists("user $user group")) {
                my $group = $config->returnValue("user $user group");
                if (   $config->isChanged("user $user")
                    || $config->isChanged("group $group"))
                {
                    my $group_seclevel =$config->returnValue("group $group seclevel");
                    if ($config->exists("user $user privacy")) {
                        if ($group_seclevel eq "auth") {
                            print"User \"$user\" have privacy, but group \"$group\" have \"auth\" as seclevel. So auth and priv work both.\n";
                        }
                    }else {
                        if ($group_seclevel eq "priv") {
                            print"User \"$user\" will not work, because he haven't privacy, but group \"$group\" have \"priv\" as seclevel.\n";
                            $haveError = 1;
                        }
                    }
                }
            }
        }
    }
    if ($haveError) {
        exit(1);
    }
}

sub copy_conf_to_tmp {

    # these files already contain SNMPv2 configuration
    copy($snmpd_conf, $snmpd_conf_tmp)
        or die "Couldn't copy $snmpd_conf to $snmpd_conf_tmp - $!";
    copy($snmpd_usr_conf, $snmpd_usr_conf_tmp)
        or die "Couldn't copy $snmpd_usr_conf to $snmpd_usr_conf_tmp - $!";
    copy($snmpd_var_conf, $snmpd_var_conf_tmp)
        or die "Couldn't copy $snmpd_var_conf to $snmpd_var_conf_tmp - $!";
}

# update all vyatta config
# can be called directly
sub snmp_update {

    copy_conf_to_tmp();

    set_tsm();

    open(my $fh, '>>', $snmpd_conf_tmp)
        or die "Couldn't open $snmpd_conf_tmp - $!";

    select $fh;

    set_views();
    set_groups();
    set_hosts();
    set_users_in_etc();

    close $fh;
    select STDOUT;

    move($snmpd_conf_tmp, $snmpd_conf)
        or die "Couldn't move $snmpd_conf_tmp to $snmpd_conf - $!";

    my $config = get_snmp_config();
    if ($config->exists("engineid")) {
        $oldEngineID = $config->returnValue("engineid");
    }

    snmpd_stop();

    #add newly added users to var config to get encrypted values
    set_users_to_other();

    move($snmpd_usr_conf_tmp, $snmpd_usr_conf)
        or die "Couldn't move $snmpd_usr_conf_tmp to $snmpd_usr_conf - $!";
    move($snmpd_var_conf_tmp, $snmpd_var_conf)
        or die "Couldn't move $snmpd_var_conf_tmp to $snmpd_var_conf - $!";

    snmpd_start();
    snmpd_stop();

    # now we have encrypted user config - start and read it after
    snmpd_start();
    update_users_vyatta_conf();
}

# validate vyatta config before write it into files
# can be called directly
sub snmp_check {
    check_user_auth_changes();
    check_relation();
    check_tsm_port();
    check_seclevel();
}

my $check_config;
my $update_snmp;
my $delete_snmp;

GetOptions(
    "check-config!" => \$check_config,
    "update-snmp!"  => \$update_snmp,
    "delete-snmp!"  => \$delete_snmp,
    "oldEngineID=s"  => \$oldEngineID,
    "setserialno=s"  => \$setserialno
);

snmp_check()  if ($check_config);
snmp_update() if ($update_snmp);
snmp_delete() if ($delete_snmp);
