#ifndef SB_COMPAT_SIGNAL_H
#define SB_COMPAT_SIGNAL_H
#include <stdint.h>
typedef struct { unsigned long __mask; } sigset_t;
typedef struct { int si_signo, si_errno, si_code; } siginfo_t;
struct sigaction {
  void (*sa_handler)(int);
  void (*sa_sigaction)(int, siginfo_t *, void *);
  sigset_t sa_mask; int sa_flags;
};
#define SA_SIGINFO 4
#define SA_RESTART 2
#define SIGPIPE 13
extern int sigaction(int, const struct sigaction *, struct sigaction *);
extern int sigemptyset(sigset_t *);
#endif
