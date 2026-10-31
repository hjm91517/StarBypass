#ifndef SB_COMPAT_STATFS_H
#define SB_COMPAT_STATFS_H
#include <stdint.h>
struct statfs {
  uint32_t f_bsize, f_iosize;
  uint64_t f_blocks, f_bfree, f_bavail, f_files, f_ffree;
  int64_t f_fsid;
  uint32_t f_owner;
  uint32_t f_type, f_flags, f_fssubtype;
  char f_fstypename[16];
  char f_mntonname[1024];
  char f_mntfromname[1024];
  uint32_t f_reserved[8];
};
extern int statfs(const char *, struct statfs *);
#endif
