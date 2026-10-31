#ifndef SB_COMPAT_MACH_H
#define SB_COMPAT_MACH_H
#include <stdint.h>
typedef uint64_t vm_address_t; typedef int vm_prot_t; typedef int kern_return_t;
typedef struct { unsigned int __x; } mach_port_t;
#define VM_PROT_READ 1
#define VM_PROT_WRITE 2
#define VM_PROT_EXECUTE 4
#define VM_PROT_COPY 0x10
#define KERN_SUCCESS 0
extern mach_port_t mach_task_self(void);
extern kern_return_t vm_protect(mach_port_t, vm_address_t, uint64_t, int, vm_prot_t);
#endif
