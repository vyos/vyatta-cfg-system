/*
 * Test if an IP address is assigned to the local system
 *
 * This uses the fact Linux will not allow binding to an address that
 * is not on the system.  It is much faster than scanning all the
 * interface addresses.
 */

#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>

int main(int argc, char **argv)
{
	int af, s;

	if (argc != 2) {
		fprintf(stderr, "Usage: %s x.x.x.x\n", argv[0]);
		return -1;
	}

	af = strchr(argv[1], ':') ? AF_INET6 : AF_INET;
	s = socket(af, SOCK_STREAM, 0);
	if (s < 0) {
		perror("socket");
		return -1;
	}

	if (af == AF_INET) {
		struct sockaddr_in sin = {
			.sin_family = AF_INET,
		};

		if (inet_pton(af, argv[1], &sin.sin_addr) <= 0) {
			fprintf(stderr, "%s: invalid address\n", argv[1]);
			return -1;
		}

		if (bind(s, (struct sockaddr *)&sin, sizeof(sin)) < 0) {
			if (errno == EADDRNOTAVAIL)
				return 1;
			perror("bind");
			return -1;
		}
	} else {
		struct sockaddr_in6 sin6;

		if (inet_pton(af, argv[1], &sin6.sin6_addr) <= 0) {
			fprintf(stderr, "%s: invalid address\n", argv[1]);
			return -1;
		}

		if (bind(s, (struct sockaddr *)&sin6, sizeof(sin6)) < 0) {
			if (errno == EADDRNOTAVAIL)
				return 1;
			perror("bind");
			return -1;
		}
	}
	return 0;
}
