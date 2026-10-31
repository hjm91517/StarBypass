#ifndef SB_COMPAT_CD_H
#define SB_COMPAT_CD_H
#include <stdint.h>
#define CC_SHA256_DIGEST_LENGTH 32
#define CC_LONG uint32_t
extern unsigned char *CC_SHA256(const void *, uint32_t, unsigned char *);
#endif
