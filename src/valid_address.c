/*
 * **** License ****
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2 as
 * published by the Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.
 * #
 * A copy of the GNU General Public License is available as
 * `/usr/share/common-licenses/GPL' in the Debian GNU/Linux distribution
 * or on the World Wide Web at `http://www.gnu.org/copyleft/gpl.html'.
 * You can also obtain it by writing to the Free Software Foundation,
 * Free Software Foundation, Inc., 51 Franklin St, Fifth Floor, Boston,
 * MA 02110-1301, USA.
 *
 * This code was originally developed by Vyatta, Inc.
 * Portions created by Vyatta are Copyright (C) 2007 Vyatta, Inc.
 * All Rights Reserved.
 *
 * This code validates IPv4 and IPv6 network prefixes using
 * the same rules as the iproute utilities. It is a replacement
 * for earlier perl code which did not scale well.
 */

#include <stdio.h>
#include <sys/types.h>
#include <string.h>
#include <stdlib.h>
#include <netinet/in.h>
#include <arpa/inet.h>

/*
 * Note: this code requires full four-tuple when specifying IPv4
 * address because the iproute utilites uses a non-standard parsing
 * (ie not inet_aton, or inet_pton)
 * because of legacy choice to parse 10.8 as 10.8.0.0 not 10.0.0.8
 */
static int valid_ipv4(const char *str)
{
	int i;
	unsigned int a[4], plen;
	uint32_t addr;	/* host order */

	if (sscanf(str, "%u.%u.%u.%u/%u", &a[0], &a[1], &a[2], &a[3], &plen)
	    != 5)
		goto bad_addr;

	addr = 0;
	for (i = 0; i < 4; i++) {
		if (a[i] > 255)
			goto bad_addr;
		addr <<= 8;
		addr |= a[i];
	}

	if (plen == 0 || plen > 32) {
		fprintf(stderr,
			"Invalid prefix len %d for IP\n", plen);
		return 0;
	}

	if (plen < 31) {
		uint32_t net_mask = ~0 << (32 - plen);
		uint32_t broadcast = (addr & net_mask) | (~0 &~ net_mask);

		if ((addr & net_mask) == addr) {
			fprintf(stderr,
				"Can not assign network address as IP address\n");
			return 0;
		}

		if (addr == broadcast) {
			fprintf(stderr,
				"Can not assign broadcast address as IP address\n");
			return 0;
		}
	}

	return 1;

 bad_addr:
	fprintf(stderr, "Invalid IPv4 address/prefix\n");
	return 0;
}

static int valid_ipv6(char *str)
{
	unsigned int prefix_len;
	struct in6_addr addr; /* net order */
	char *slash, *endp;

	slash = strchr(str, '/');
	if (!slash) {
		fprintf(stderr, "Missing network prefix\n");
		return 0;
	}

	*slash++ = 0;
	prefix_len = strtoul(slash, &endp, 10);
	if (*slash == '\0' || *endp != '\0')
		fprintf(stderr, "Non-digit in prefix length\n");

	else if (prefix_len <= 1 || prefix_len > 128)
		fprintf(stderr,
			"Invalid prefix len %d for IPv6\n", prefix_len);

	else if (inet_pton(AF_INET6, str, &addr) <= 0)
		fprintf(stderr, "Invalid IPv6 address\n");

	else if (IN6_IS_ADDR_LINKLOCAL(&addr))
		fprintf(stderr,
			"Can not assign an address reserved for IPv6 link local\n");
	else if (IN6_IS_ADDR_MULTICAST(&addr))
		fprintf(stderr,
			"Can not assign an address reserved for IPv6 multicast\n");
	else if (IN6_IS_ADDR_UNSPECIFIED(&addr))
		fprintf(stderr,
			"Can not assign IPv6 reserved for IPv6 unspecified address\n");
	else 
		return 1;	/* is valid address and prefix */

	return 0;	/* Invalid address */
}


static int valid_prefix(char *str)
{
	if (strcmp(str, "dhcp") == 0 || strcmp(str, "dhcpv6") == 0)
		return 1;

	if (strchr(str, ':') == NULL)
		return valid_ipv4(str);
	else
		return valid_ipv6(str);
}

int main(int argc, char **argv)
{
	while (--argc) {
		if (!valid_prefix(*++argv))
			return 1;
	}
	return 0;
}
