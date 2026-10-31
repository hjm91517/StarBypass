// 07-bootstrap.m — 装配层
#import "01-shared.h"
#import <UIKit/UIKit.h>

extern void RCInstallGuard(void);
extern void RCInstallStealth(void);
extern void RCInstallCapture(void);
extern void RCInstallTrace(void);
extern void RCInstallUI(void);
extern void RCInstallUIWindow(void);
extern void RCInstallUIPresentHook(void);

static void rc_banner(void) {
    NSBundle *b = [NSBundle mainBundle];
    NSDictionary *info = [b infoDictionary];

    RCSection(@"侦察会话开始");
    RC(@"构建: %s", RC_CFG_BUILD_ID);
    RC(@"应用: %@ (%@)", [info objectForKey:@"CFBundleName"],
       [info objectForKey:@"CFBundleIdentifier"]);
    RC(@"版本: %@ build %@", [info objectForKey:@"CFBundleShortVersionString"],
       [info objectForKey:@"CFBundleVersion"]);
    RC(@"系统: %@", [[UIDevice currentDevice] systemVersion]);
    RC(@"机型: %@", [[UIDevice currentDevice] model]);
    RC(@"日志文件: %@", RCLogPath() ? RCLogPath() : @"(不可写)");
    RCSection(@"");
}

static void rc_boot(void) {
    if (!RCOpenLog()) {
        // 仍然继续，只靠 NSLog
    }
    rc_banner();

    RCInstallGuard();
    RCInstallUIPresentHook();
    RCInstallStealth();
    RCInstallCapture();
    RCInstallTrace();
    RCInstallUI();

    // UI：立刻试一次，失败会自动重试（内部每 1.5s 一次，最多 60 次）
    RCAfterSec(0.3, ^{
        RCInstallUIWindow();
    });

    RCSection(@"装配完成，请触发一次卡密验证");
    RC(@"日志实时写入: %@", RCLogPath() ? RCLogPath() : @"(仅 NSLog)");
    RCFlush();
}

__attribute__((constructor))
static void RCInit(void) {
    RCAsyncMain(^{
        rc_boot();

        // 类可能延迟加载，补一次
        RCAfterSec(2.0, ^{
            RCSection(@"补挂（2s）");
            RCInstallTrace();
            RCInstallUI();
            RCSection(@"补挂完成");
            RCFlush();
        });
    });
}
