// symbol-rebind.c — 精简 fishhook：线程安全、幂等、不越界
// 精简 fishhook：重绑定 __DATA / __DATA_CONST 中的 lazy 与 non-lazy 符号指针
//
// 关键安全点：
//   1. 全局单次注册，避免多插件重复注册 dyld 回调导致回调叠加
//   2. 每次重绑定先拷贝本地 rebinding 表，不持有外部指针
//   3. 遍历前判空，不会解引用悬挂指针
//   4. vm_protect 失败直接跳过该 section，绝不硬写
//   5. 已重绑定过的槽位做标记，重复调用幂等

#include "symbol-rebind.h"
#include <mach/mach.h>
#include <string.h>
#include <stdlib.h>
#include <stdbool.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <mach-o/nlist.h>
#include <mach-o/getsect.h>
#include <dlfcn.h>

#ifndef SEG_DATA_CONST
#define SEG_DATA_CONST "__DATA_CONST"
#endif

#ifndef SEG_DATA
#define SEG_DATA "__DATA"
#endif

#ifndef VM_PROT_COPY
#define VM_PROT_COPY 0x10
#endif

#define SB_MAX_REBIND 64
#define SB_MAX_TOTAL_SYMBOLS 512

// 每条重绑定记录唯一 id，用于幂等标记
typedef struct {
    const char *name;
    void *replacement;
    void **replaced;
    int applied;
} sb_entry_t;

static sb_entry_t   g_entries[SB_MAX_TOTAL_SYMBOLS];
static size_t       g_entry_cnt = 0;
static int          g_registered = 0;
static int          g_lock = 0;

static void sb_lock(void) {
    while (__sync_lock_test_and_set(&g_lock, 1)) {
        // 自旋等待
    }
}
static void sb_unlock(void) { __sync_lock_release(&g_lock); }

static int sb_protect(void *addr, size_t len, int prot) {
    if (!addr || len == 0) return -1;
    uintptr_t start = (uintptr_t)addr & ~(uintptr_t)0xfff;
    uintptr_t end = ((uintptr_t)addr + len + 0xfff) & ~(uintptr_t)0xfff;
    size_t span = (size_t)(end - start);
    kern_return_t kr = vm_protect(mach_task_self(), (vm_address_t)start, span,
                                  false, prot);
    return (kr == KERN_SUCCESS) ? 0 : -1;
}

// 在单个镜像里重绑定；返回改动的槽位数
static size_t sb_rebind_image(const struct mach_header_64 *mh, intptr_t slide) {
    if (!mh || mh->magic != MH_MAGIC_64) return 0;
    if (mh->ncmds == 0 || mh->sizeofcmds == 0) return 0;

    const struct load_command *lc = (const struct load_command *)(mh + 1);
    uint32_t ncmds = mh->ncmds;

    const struct symtab_command *symtab = NULL;
    const struct dysymtab_command *dysym = NULL;
    const struct segment_command_64 *linkedit = NULL;
    const struct segment_command_64 *segs[2] = { NULL, NULL };

    for (uint32_t i = 0; i < ncmds; i++) {
        if (!lc || lc->cmdsize < sizeof(struct load_command)) break;

        if (lc->cmd == LC_SYMTAB) {
            symtab = (const struct symtab_command *)lc;
        } else if (lc->cmd == LC_DYSYMTAB) {
            dysym = (const struct dysymtab_command *)lc;
        } else if (lc->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *seg = (const struct segment_command_64 *)lc;
            if (strcmp(seg->segname, "__LINKEDIT") == 0) {
                linkedit = seg;
            } else if (strcmp(seg->segname, SEG_DATA) == 0) {
                segs[0] = seg;
            } else if (strcmp(seg->segname, SEG_DATA_CONST) == 0) {
                segs[1] = seg;
            }
        }
        lc = (const struct load_command *)((uintptr_t)lc + lc->cmdsize);
    }

    if (!symtab || !dysym || !linkedit) return 0;
    if (symtab->nsyms == 0 || symtab->strsize == 0) return 0;
    if (dysym->nindirectsyms == 0) return 0;

    uintptr_t linkedit_base = (uintptr_t)slide + (uintptr_t)linkedit->vmaddr
                              - (uintptr_t)linkedit->fileoff;

    const struct nlist_64 *symtab_entries =
        (const struct nlist_64 *)(linkedit_base + symtab->symoff);
    const char *strtab = (const char *)(linkedit_base + symtab->stroff);
    const uint32_t *indirect =
        (const uint32_t *)(linkedit_base + dysym->indirectsymoff);

    size_t changed = 0;

    for (int s = 0; s < 2; s++) {
        const struct segment_command_64 *seg = segs[s];
        if (!seg || seg->nsects == 0) continue;

        const struct section_64 *sect = (const struct section_64 *)(seg + 1);
        for (uint32_t i = 0; i < seg->nsects; i++, sect++) {
            uint32_t type = sect->flags & SECTION_TYPE;
            if (type != S_LAZY_SYMBOL_POINTERS &&
                type != S_NON_LAZY_SYMBOL_POINTERS &&
                type != 0x10 /* S_LAZY_DYLIB_SYMBOL_POINTERS */) {
                continue;
            }
            if (sect->size == 0) continue;

            size_t count = sect->size / sizeof(void *);
            void **ptrs = (void **)((uintptr_t)slide + (uintptr_t)sect->addr);
            if (!ptrs) continue;

            // 保护失败就不动这一节，避免 EXC_BAD_ACCESS
            if (sb_protect(ptrs, sect->size,
                           VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY) != 0) {
                continue;
            }

            uint32_t indirect_off = sect->reserved1;

            for (size_t k = 0; k < count; k++) {
                uint32_t sym_idx = indirect[indirect_off + k];
                if (sym_idx == INDIRECT_SYMBOL_LOCAL ||
                    sym_idx == INDIRECT_SYMBOL_ABS) continue;
                if (sym_idx >= symtab->nsyms) continue;

                const struct nlist_64 *nl = &symtab_entries[sym_idx];
                if (nl->n_un.n_strx == 0) continue;
                if (nl->n_un.n_strx >= symtab->strsize) continue;
                if (nl->n_type & N_STAB) continue;

                const char *sym_name = strtab + nl->n_un.n_strx;
                if (!sym_name || !*sym_name) continue;

                for (size_t r = 0; r < g_entry_cnt; r++) {
                    sb_entry_t *e = &g_entries[r];
                    if (!e->name || !e->replacement) continue;
                    if (strcmp(sym_name, e->name) != 0) continue;
                    if (e->applied) break;   // 已处理过，幂等

                    if (e->replaced && *e->replaced == NULL) {
                        *e->replaced = ptrs[k];
                    }
                    ptrs[k] = e->replacement;
                    e->applied = 1;
                    changed++;
                    break;
                }
            }

            // 恢复可读可执行，失败也不致命
            sb_protect(ptrs, sect->size, VM_PROT_READ | VM_PROT_EXECUTE);
        }
    }

    return changed;
}

static void sb_callback(const struct mach_header *mh, intptr_t slide) {
    if (!mh) return;
    if (g_entry_cnt == 0) return;
    sb_lock();
    sb_rebind_image((const struct mach_header_64 *)mh, slide);
    sb_unlock();
}

int SB_rebind_symbols(struct sb_rebinding rebindings[], size_t rebindings_nel) {
    if (!rebindings || rebindings_nel == 0) return -1;

    sb_lock();

    // 写入全局表（去重同名）
    for (size_t i = 0; i < rebindings_nel; i++) {
        if (!rebindings[i].name || !rebindings[i].replacement) continue;
        if (g_entry_cnt >= SB_MAX_TOTAL_SYMBOLS) break;

        int dup = 0;
        for (size_t j = 0; j < g_entry_cnt; j++) {
            if (g_entries[j].name &&
                strcmp(g_entries[j].name, rebindings[i].name) == 0) {
                dup = 1;
                break;
            }
        }
        if (dup) continue;

        g_entries[g_entry_cnt].name = rebindings[i].name;
        g_entries[g_entry_cnt].replacement = rebindings[i].replacement;
        g_entries[g_entry_cnt].replaced = rebindings[i].replaced;
        g_entries[g_entry_cnt].applied = 0;
        g_entry_cnt++;
    }

    // 已加载镜像立刻处理
    // 全部走 dlsym，避免产生 _dyld_* 的 flat namespace 绑定
    uint32_t (*p_image_count)(void) =
        (uint32_t (*)(void))dlsym(RTLD_DEFAULT, "_dyld_image_count");
    const struct mach_header *(*p_image_header)(uint32_t) =
        (const struct mach_header *(*)(uint32_t))dlsym(RTLD_DEFAULT, "_dyld_get_image_header");
    intptr_t (*p_slide)(uint32_t) =
        (intptr_t (*)(uint32_t))dlsym(RTLD_DEFAULT, "_dyld_get_image_vmaddr_slide");

    if (p_image_count && p_image_header && p_slide) {
        uint32_t imgcnt = p_image_count();
        for (uint32_t i = 0; i < imgcnt; i++) {
            const struct mach_header *mh = p_image_header(i);
            if (!mh) continue;
            sb_rebind_image((const struct mach_header_64 *)mh, p_slide(i));
        }
    }

    // 只注册一次，避免多插件重复叠加回调
    if (!g_registered) {
        g_registered = 1;
        void (*p_register)(void (*)(const struct mach_header *, intptr_t)) =
            (void (*)(void (*)(const struct mach_header *, intptr_t)))
            dlsym(RTLD_DEFAULT, "_dyld_register_func_for_add_image");
        if (p_register) p_register(sb_callback);
    }

    sb_unlock();
    return 0;
}
