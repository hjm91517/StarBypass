#ifndef SB_COMPAT_DLFCN_H
#define SB_COMPAT_DLFCN_H
#define RTLD_DEFAULT ((void*)0)
#define RTLD_NOW 2
extern void *dlopen(const char *, int);
extern void *dlsym(void *, const char *);
#endif
