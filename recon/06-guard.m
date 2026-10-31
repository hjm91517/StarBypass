// 06-guard.m — 防崩层
#import "01-shared.h"
#include <signal.h>
#include <string.h>

static void rc_onException(NSException *e) {
    RC(@"[guard] 未捕获异常 %@: %@", [e name], [e reason]);
}

static void rc_onSignal(int sig) {
    RC(@"[guard] 忽略信号 %d", sig);
}

void RCInstallGuard(void) {
    static int done = 0;
    if (done) return;
    done = 1;

    NSSetUncaughtExceptionHandler(&rc_onException);

    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = rc_onSignal;
    sa.sa_flags = SA_RESTART;
    sigemptyset(&sa.sa_mask);
    sigaction(SIGPIPE, &sa, NULL);

    RC(@"[guard] 已启用");
}
