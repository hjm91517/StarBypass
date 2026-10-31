#ifndef SB_COMPAT_OS_LOCK_H
#define SB_COMPAT_OS_LOCK_H
typedef struct { int _os_unfair_lock_opaque; } os_unfair_lock, *os_unfair_lock_t;
#define OS_UNFAIR_LOCK_INIT {0}
extern void os_unfair_lock_lock(os_unfair_lock_t);
extern void os_unfair_lock_unlock(os_unfair_lock_t);
#endif
