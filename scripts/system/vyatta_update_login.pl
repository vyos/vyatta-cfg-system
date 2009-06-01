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

foreach my $type ($config->listNodes()) {
    my $kind = ucfirst $type;
    my $location = "Vyatta/Login/$kind.pm";
    my $class    = "Vyatta::Login::$kind";
    
    require $location;

    my $obj =  $class->new();
    die "Don't understand $type" unless $obj;

    $obj->update();
}
