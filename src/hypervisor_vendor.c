/*
 * Identify hypervisor vendor
 *
 * based on code from util-linux lscpu
 */

#include <stdio.h>
#include <string.h>

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
		return "Unknown";
}

int main(int argc, char **argv)
{
	const char *vm = get_hypervisor();

	if (vm) {
		printf("%s\n", vm);
		return 0;
	} else
		return 1;
}
