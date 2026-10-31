#ifndef SB_COMPAT_STDIO_H
#define SB_COMPAT_STDIO_H
#include <stddef.h>
typedef struct __sFILE FILE;
extern FILE *fopen(const char *, const char *);
extern int printf(const char *, ...);
extern int fclose(FILE *);
extern int fflush(FILE *);
extern size_t fwrite(const void *, size_t, size_t, FILE *);
extern int fseek(FILE *, long, int);
extern long ftell(FILE *);
#define SEEK_END 2
#endif
