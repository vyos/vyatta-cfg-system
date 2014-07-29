/*
 * Identify hypervisor vendor
 *
 * This is based on code from lscpu and virt-what. Unfortunately, neither
 * of those is sufficient.  lscpu doesn't detect many VM's,
 * and virt-what is a shell script that has to be run as root.
 * 
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
 * Portions created by Vyatta are Copyright (C) 2011 Vyatta, Inc.
 * All Rights Reserved.
 */

#include <stdio.h>
#include <string.h>
#include <unistd.h>

#define PROC_XEN	"/proc/xen"
#define PROC_XENCAP	PROC_XEN  "/capabilities"
#define PROC_PCIDEVS	"/proc/bus/pci/devices"
#define SYS_HYPERVISOR  "/sys/hypervisor/type"
#define SYS_DMI_VENDOR  "/sys/class/dmi/id/sys_vendor"

#if defined(__x86_64__) || defined(__i386__)

/*
 * This CPUID leaf returns the information about the hypervisor.
 * EAX : maximum input value for CPUID supported by the hypervisor.
 * EBX, ECX, EDX : Hypervisor vendor ID signature. E.g. VMwareVMware.
 */
#define HYPERVISOR_INFO_LEAF   0x40000000

static inline void
cpuid(unsigned int op, unsigned int *eax, unsigned int *ebx,
			 unsigned int *ecx, unsigned int *edx)
{
	__asm__(
#if defined(__PIC__) && defined(__i386__)
		/* x86 PIC cannot clobber ebx -- gcc bitches */
		"pushl %%ebx;"
		"cpuid;"
		"movl %%ebx, %%esi;"
		"popl %%ebx;"
		: "=S" (*ebx),
#else
		"cpuid;"
		: "=b" (*ebx),
#endif
		  "=a" (*eax),
		  "=c" (*ecx),
		  "=d" (*edx)
		: "1" (op), "c"(0));
}


/* Use CPUID instruction to find hypervisor vendor.
 * This is the preferred method, but doesn't work with older
 * hypervisors.
 */
static const char *get_hypervisor_cpuid(void)
{
	unsigned int eax = 0, ebx = 0, ecx = 0, edx = 0;
	char hyper_vendor_id[13];

	memset(hyper_vendor_id, 0, sizeof(hyper_vendor_id));

	cpuid(HYPERVISOR_INFO_LEAF, &eax, &ebx, &ecx, &edx);
	memcpy(hyper_vendor_id + 0, &ebx, 4);
	memcpy(hyper_vendor_id + 4, &ecx, 4);
	memcpy(hyper_vendor_id + 8, &edx, 4);
	hyper_vendor_id[12] = '\0';

	if (!hyper_vendor_id[0])
		return NULL;

	else if (!strncmp("XenVMMXenVMM", hyper_vendor_id, 12))
		return "Xen hvm";
	else if (!strncmp("KVMKVMKVM", hyper_vendor_id, 9))
		return "KVM";
	else if (!strncmp("Microsoft Hv", hyper_vendor_id, 12))
		return "Microsoft HyperV";
	else if (!strncmp("VMwareVMware", hyper_vendor_id, 12))
		return "VMware";
	else
		return NULL;
}

#else   /* ! __x86_64__ */
static const char *get_hypervisor_cpuid(void)
{
return NULL;
}
#endif

/* Use DMI vendor information */
static const char *get_hypervisor_dmi(void)
{
	FILE *f = fopen(SYS_DMI_VENDOR, "r");
	char vendor_id[128];

	if (!f)
		return NULL;

	if (fgets(vendor_id, sizeof(vendor_id), f) == NULL) {
		fclose(f);
		return NULL;
	}
	fclose(f);
	
	if (!strncmp(vendor_id, "VMware", 6))
		return "VMware";
	/* Note: Hyper-V has same DMI, but different CPUID */
	else if (!strncmp(vendor_id, "Microsoft Corporation", 21))
		return "VirtualPC";
	else if (!strncmp(vendor_id, "innotek GmbH", 12))
		return "VirtualBox";
	else if (!strncmp(vendor_id, "Parallels", 9))
		return "Parallels";
	else
		return NULL;
}

static int
has_pci_device(int vendor, int device)
{
	FILE *f;
	int num, fn, ven, dev;
	int res = 1;

	f = fopen(PROC_PCIDEVS, "r");
	if (!f)
		return 0;

	 /* for more details about bus/pci/devices format see
	  * drivers/pci/proc.c in linux kernel
	  */
	while(fscanf(f, "%02x%02x\t%04x%04x\t%*[^\n]",
			&num, &fn, &ven, &dev) == 4) {

		if (ven == vendor && dev == device)
			goto found;
	}

	res = 0;
found:
	fclose(f);
	return res;
}

int main(int argc, char **argv)
{
	FILE *f;
	const char *hvm;
	char buf[256];

	if ((hvm = get_hypervisor_cpuid()) != NULL ||
	    (hvm = get_hypervisor_dmi()) != NULL)
		printf("%s\n", hvm);

	/* Grotty code to look for old Xen */
	else if ((f = fopen(PROC_XENCAP, "r")) != NULL) {
		int dom0 = 0;

		if (fscanf(f, "%s", buf) == 1 &&
		    !strcmp(buf, "control_d"))
			dom0 = 1;
		printf("Xen %s\n", dom0 ? "dom0" : "domU");
		fclose(f);
	}
	else if ((f = fopen(SYS_HYPERVISOR, "r")) != NULL) {
		if (fgets(buf, sizeof(buf), f) != NULL
		    && !strncmp(buf, "xen", 3))
			printf("Xen\n");
		fclose(f);
	}
	else if (has_pci_device(0x5853, 0x0001)) {
		/* Xen full-virt on non-x86_64 */
		printf("Xen full\n");
	}

	/* print nothing if in real mode */
	return 0;
}
