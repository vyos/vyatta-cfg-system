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
# A copy of the GNU General Public License is available as
# `/usr/share/common-licenses/GPL' in the Debian GNU/Linux distribution
# or on the World Wide Web at `http://www.gnu.org/copyleft/gpl.html'.
# You can also obtain it by writing to the Free Software Foundation,
# Free Software Foundation, Inc., 51 Franklin St, Fifth Floor, Boston,
# MA 02110-1301, USA.
#
# This code was originally developed by Vyatta, Inc.
# Portions created by Vyatta are Copyright (C) 2009 Vyatta, Inc.
# All Rights Reserved.
#
# Author: Stig Thormodsrud
# Date: April 2009
# Description: Script to setup login banner
#
# **** End License ****
#

use lib '/opt/vyatta/share/perl5/';
use Vyatta::Config;

use Getopt::Long;
use File::Copy;
use File::Compare;
use strict;
use warnings;

my $prelogin_file      = '/etc/issue';
my $prelogin_net_file  = '/etc/issue.net';
my $postlogin_file     = '/etc/motd';


sub save_orig_file {
    my $file = shift;

    move($file, "$file.old") if ! -e "$file.old";
    return;
}

sub restore_orig_file {
    my $file = shift;

    move("$file.old", $file)if -e "$file.old"; 
    return;
}

sub is_same_as_file {
    my ($file, $value) = @_;

    return if ! -e $file;

    my $mem_file = ' ';
    open my $MF, '+<', \$mem_file or die "couldn't open memfile $!\n";
    print $MF $value;
    seek($MF, 0, 0);
    
    my $rc = compare($file, $MF);
    return 1 if $rc == 0;
    return;
}

sub write_file_value {
    my ($file, $value) = @_;

    # Avoid unnecessary writes.  At boot the file will be the
    # regenerated with the same content.
    return if is_same_as_file($file, $value);

    open my $F, '>', $file or die "Error: opening $file [$!]";
    print $F "$value";
    close $F;
}

sub get_banner {
    my $banner_type = shift;

    my $config = new Vyatta::Config;
    $config->setLevel('system login banner');
    my $text = $config->returnValue($banner_type);
    $text =~ s|\\n|\n|g;
    $text =~ s|\\t|\t|g;
    return $text;
}

sub add_prelogin {
    save_orig_file($prelogin_file);
    save_orig_file($prelogin_net_file);
    my $text = get_banner('pre-login');
    write_file_value($prelogin_file, $text);    
    write_file_value($prelogin_net_file, $text);    
    return;
}

sub add_postlogin {
    save_orig_file($postlogin_file);
    my $text = get_banner('post-login');
    write_file_value($postlogin_file, $text);
    return;
}


#
# main
#
my ($action, $banner_type);

GetOptions("action=s"      => \$action,
	   "banner-type=s" => \$banner_type,
);

die "Error: no action"      if ! defined $action;
die "Error: no banner-type" if ! defined $banner_type;

if ($action eq 'update') {
    if ($banner_type eq 'pre-login') {
	add_prelogin();
	exit 0;
    }
    if ($banner_type eq 'post-login') {
	add_postlogin();
	exit 0;
    }
}

if ($action eq 'delete') {
    if ($banner_type eq 'pre-login') {
	restore_orig_file($prelogin_file);
	restore_orig_file($prelogin_net_file);
	exit 0;
    }
    if ($banner_type eq 'post-login') {
	restore_orig_file($postlogin_file);
	exit 0;
    }
}

exit 1;

#end of file
