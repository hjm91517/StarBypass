#ifndef SB_COMPAT_STDIO_H
#define SB_COMPAT_STDIO_H
#include <stddef.h>
typedef struct __sFILE FILE;
extern FILE *fopen(const char *, const char *);
extern int printf(const char *, ...);
#endif
