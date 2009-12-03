#!/usr/bin/perl

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
# Portions created by Vyatta are Copyright (C) 2007 Vyatta, Inc.
# All Rights Reserved.
#
# **** End License ****

use strict;
use lib "/opt/vyatta/share/perl5";
use Vyatta::Config;

# This is just a simple wrapper that allows for extensiblility
# of login types.

my $config = new Vyatta::Config;
$config->setLevel("system login");

my %loginNodes = $config->listNodeStatus();
while ( my ($type, $status) = each %loginNodes) {
    next if ($status eq 'static');
    next if ($type eq 'banner');

    # convert radius-server to RadiusServer
    my $kind = ucfirst $type;
    $kind =~ s/-server/Server/;

    # Dynamically load the module to handle that login method
    require "Vyatta/Login/$kind.pm";

    # Dynamically invoke update for this type
    my $login    = "Vyatta::Login::$kind";
    $login->update($status);
}
