#ifndef SB_COMPAT_LOADER_H
#define SB_COMPAT_LOADER_H
#include <stdint.h>
#define MH_MAGIC_64 0xfeedfacf
#define LC_SEGMENT_64 0x19
#define LC_SYMTAB 0x2
#define LC_DYSYMTAB 0xb
#define SECTION_TYPE 0x000000ff
#define S_LAZY_SYMBOL_POINTERS 0x7
#define S_NON_LAZY_SYMBOL_POINTERS 0x6
#define S_LAZY_DYLIB_SYMBOL_POINTERS 0x10
#define INDIRECT_SYMBOL_LOCAL 0x80000000
#define INDIRECT_SYMBOL_ABS 0x40000000
#define N_STAB 0xe0
struct mach_header_64 {
  uint32_t magic, cputype, cpusubtype, filetype, ncmds, sizeofcmds, flags, reserved;
};
struct load_command { uint32_t cmd, cmdsize; };
struct segment_command_64 {
  uint32_t cmd, cmdsize;
  char segname[16];
  uint64_t vmaddr, vmsize, fileoff, filesize;
  int32_t maxprot, initprot;
  uint32_t nsects, flags;
};
struct section_64 {
  char sectname[16], segname[16];
  uint64_t addr, size;
  uint32_t offset, align, reloff, nreloc, flags, reserved1, reserved2, reserved3;
};
struct symtab_command { uint32_t cmd, cmdsize, symoff, nsyms, stroff, strsize; };
struct dysymtab_command {
  uint32_t cmd, cmdsize, ilocalsym, nlocalsym, iextdefsym, nextdefsym,
           iundefsym, nundefsym, tocoff, ntoc, modtaboff, nmodtab,
           extrefsymoff, nextrefsyms, indirectsymoff, nindirectsyms,
           extreloff, nextrel, locreloff, nlocrel;
};
struct nlist_64 {
  union { uint32_t n_strx; } n_un;
  uint8_t n_type, n_sect;
  uint16_t n_desc;
  uint64_t n_value;
};
#endif
