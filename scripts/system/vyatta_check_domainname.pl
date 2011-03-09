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
# Portions created by Vyatta are Copyright (C) 2010 Vyatta, Inc.
# All Rights Reserved.
#
# **** End License ****

use strict;
use warnings;

# Source: http://en.wikipedia.org/wiki/Domain_Name_System
# Rules for forming domain names appear in RFC 1035, RFC 1123, and RFC 2181.
# A domain name consists of one or more parts, technically called labels,
# that are conventionally concatenated, and delimited by dots, 
# such as example.com.
#
#  * The right-most label conveys the top-level domain; for example,
#   the domain name www.example.com belongs to the top-level domain com.
#  * The hierarchy of domains descends from right to left; each label to
#    the left specifies a subdivision, or subdomain of the domain to the
#    right. For example: the label example specifies a subdomain of the
#    com domain, and www is a sub domain of example.com. This tree of
#    subdivisions may have up to 127 levels.
# 
# * Each label may contain up to 63 characters. The full domain name may
#   not exceed a total length of 253 characters in its external
#   dotted-label specification.[10] In the internal binary
#   representation of the DNS the maximum length requires 255 octets of
#   storage.[3] In practice, some domain registries may have shorter
#   limits.[citation needed]
# 
#  * DNS names may technically consist of any character representable in
#    an octet. However, the allowed formulation of domain names in the
#    DNS root zone, and most other sub domains, uses a preferred format
#    and character set. The characters allowed in a label are a subset
#    of the ASCII character set, and includes the characters a through
#    z, A through Z, digits 0 through 9, and the hyphen. This rule is
#    known as the LDH rule (letters, digits, hyphen). Domain names are
#    interpreted in case-independent manner. Labels may not start or end
#    with a hyphen.[11]

foreach my $fqdn (@ARGV) {
    die "$fqdn: full domain length exceeds 253 characters\n"
	if length($fqdn) > 253;

    my @label = split /\./, $fqdn;
    die "$fqdn: domain name greater than 127 levels\n"
	if ($#label > 127);

    foreach my $label (@label) {
	die "$label: invalid character in domain name\n"
	    unless $label =~ /^[-0-9a-zA-Z]+$/;

	die "$label: label must not start or end with hyphen\n"
	    if $label =~ /(^-)|(-$)/;

	die "$label: domain name element greater than 63 characters\n"
	    if (length($label) > 63);
    }
}
    
