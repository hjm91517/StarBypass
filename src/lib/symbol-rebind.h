// symbol-rebind.h
// 精简 fishhook：用于在已加载的 Mach-O 镜像上重绑定符号
#ifndef SB_SYMBOL_REBIND_H
#define SB_SYMBOL_REBIND_H

#include <stddef.h>
#include <stdint.h>

struct sb_rebinding {
    const char *name;
    void *replacement;
    void **replaced;
};

int SB_rebind_symbols(struct sb_rebinding rebindings[], size_t rebindings_nel);

#endif
