#ifndef SB_COMPAT_STRING_H
#define SB_COMPAT_STRING_H
#include <stddef.h>
extern void *memcpy(void *, const void *, size_t);
extern void *memset(void *, int, size_t);
extern size_t strlen(const char *);
extern int strcmp(const char *, const char *);
extern int strncmp(const char *, const char *, size_t);
extern char *strncpy(char *, const char *, size_t);
extern char *strcasestr(const char *, const char *);
#endif
