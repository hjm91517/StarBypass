#ifndef SB_COMPAT_DYLD_H
#define SB_COMPAT_DYLD_H
#include <stdint.h>
#include <mach-o/loader.h>
extern uint32_t _dyld_image_count(void);
extern const struct mach_header *_dyld_get_image_header(uint32_t);
extern intptr_t _dyld_get_image_vmaddr_slide(uint32_t);
extern const char *_dyld_get_image_name(uint32_t);
extern void _dyld_register_func_for_add_image(void (*f)(const struct mach_header *, intptr_t));
#endif
