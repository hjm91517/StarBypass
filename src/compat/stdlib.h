#ifndef SB_COMPAT_STDLIB_H
#define SB_COMPAT_STDLIB_H
#include <stddef.h>
extern void *calloc(size_t, size_t);
extern void *malloc(size_t);
extern void free(void *);
#endif
