// 06-guard.m — 稳定层：全局防崩溃保护
//
// 只做两件事，不掩盖逻辑错误：
//   1. 未捕获的 NSException 记录后吞掉，不让它终止进程
//   2. SIGPIPE 忽略（网络写失败在 hook 场景下很常见）
//
// 不接管 SIGSEGV / SIGBUS：那类错误说明代码有真 bug，掩盖只会让问题更隐蔽。

#import "01-shared.h"
#include <signal.h>
#include <string.h>

static void SB_onUncaughtException(NSException *e) {
    SBLog(@"[guard] 未捕获异常 name=%@ reason=%@", [e name], [e reason]);
}

static void SB_onSignal(int sig) {
    SBLog(@"[guard] 忽略信号 %d", sig);
}

void SB_installGuard(void) {
    static int done = 0;
    if (done) return;
    done = 1;

    NSSetUncaughtExceptionHandler(&SB_onUncaughtException);

    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = SB_onSignal;
    sa.sa_flags = SA_RESTART;
    sigemptyset(&sa.sa_mask);
    sigaction(SIGPIPE, &sa, NULL);

    SBLog(@"[guard] 崩溃防护已启用");
}
