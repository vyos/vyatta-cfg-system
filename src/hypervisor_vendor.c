/*
 * Identify hypervisor vendor
 *
 * based on code from util-linux lscpu
 */

#include <stdio.h>
#include <string.h>
#include <unistd.h>

#define PROC_XEN	"/proc/xen"
#define PROC_XENCAP	PROC_XEN  "/capabilities"
#define PROC_PCIDEVS	"/proc/bus/pci/devices"

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

static const char *get_hypervisor(void)
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
		return "Xen";
	else if (!strncmp("KVMKVMKVM", hyper_vendor_id, 9))
		return "KVM";
	else if (!strncmp("Microsoft Hv", hyper_vendor_id, 12))
		return "Microsoft HyperV";
	else if (!strncmp("VMwareVMware", hyper_vendor_id, 12))
		return "VMware";
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
	const char *hvm = get_hypervisor();

	if (hvm)
		printf("%s\n", hvm);

	/* Grotty code to look for old Xen */
	else if (access(PROC_XEN, F_OK) == 0) {
		FILE *fd = fopen(PROC_XENCAP, "r");
		int dom0 = 0;

		if (fd) {
			char buf[256];

			if (fscanf(fd, "%s", buf) == 1 &&
			    !strcmp(buf, "control_d"))
				dom0 = 1;
			fclose(fd);
		}
		printf("Xen %s\n", dom0 ? "none" : "para");
	}

	else if (has_pci_device(0x5853, 0x0001)) {
		/* Xen full-virt on non-x86_64 */
		printf("Xen full\n");
	}

	/* print nothing if in real mode */
	return 0;
}
