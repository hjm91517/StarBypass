// 04-license.m — 授权层：最小侵入接管
//
// 设计原则（针对"不破坏原逻辑"）：
//   1. 只接管返回 BOOL 的方法 → 恒 YES。返回类型窄，签名兼容，零副作用。
//   2. void 回调类方法 → 调用原实现，但把 success 改成 YES、message 改成成功文案。
//      保留原调用链，不改变控制流。
//   3. 不接管单例 +xK7vQ2mN —— 原实现要初始化状态，替换会破坏内部状态。
//   4. 不接管返回对象的方法（过期时间等）—— 返回类型/语义不明，猜错就会崩。
//
// 上一版替换了单例和返回对象的方法，属于典型过度侵入，已移除。

#import "01-shared.h"
#import <UIKit/UIKit.h>
#include <stdlib.h>

#pragma mark - 通用布尔真

static BOOL SB_retYES(id self, SEL _cmd) { return YES; }

// 按返回类型批量接管
static int SB_hookBoolMethods(Class cls) {
    if (!cls) return 0;

    int hooked = 0;
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    if (!methods) return 0;

    for (unsigned int i = 0; i < count; i++) {
        SEL sel = method_getName(methods[i]);
        const char *enc = method_getTypeEncoding(methods[i]);
        if (!enc || !enc[0]) continue;

        char ret = enc[0];
        if (ret != 'B' && ret != 'c') continue;   // 只碰布尔返回

        IMP orig = method_getImplementation(methods[i]);
        SB_storeIMP(NSStringFromClass(cls), NSStringFromSelector(sel), orig);
        class_replaceMethod(cls, sel, (IMP)SB_retYES, enc);
        hooked++;
    }
    free(methods);
    return hooked;
}

#pragma mark - 结果回调：调用原实现但改参数

// -hV8nD3sJ:success:message:expiry:
// 保留原调用链，把 success/message 换掉，避免 app 记录失败态
static void SB_resultCallback(id self, SEL _cmd, id a, BOOL ok, id msg, id exp) {
    typedef void (*PFN)(id, SEL, id, BOOL, id, id);
    static PFN orig = NULL;
    static int done = 0;
    if (!done) {
        orig = (PFN)SB_origIMP(NSStringFromClass([self class]),
                               NSStringFromSelector(_cmd));
        done = 1;
    }

    SBLog(@"结果回调：原 success=%d，改写为 1", (int)ok);
    SB_persistAuthorized(nil, nil);

    if (orig) {
        orig(self, _cmd, a, YES, @"激活成功", exp);
    }
}

// 状态文案：调用原实现，改为已授权
static void SB_statusText(id self, SEL _cmd, id text) {
    typedef void (*PFN)(id, SEL, id);
    static PFN orig = NULL;
    static int done = 0;
    if (!done) {
        orig = (PFN)SB_origIMP(NSStringFromClass([self class]),
                               NSStringFromSelector(_cmd));
        done = 1;
    }
    NSString *ok = [NSString stringWithUTF8String:SB_CFG_SUCCESS_TEXT];
    SBLog(@"状态文案 → %@", ok);
    if (orig) orig(self, _cmd, ok);
}

#pragma mark - 安装

void SB_installLicense(void) {
    NSString *authName = [NSString stringWithUTF8String:SB_CFG_AUTH_CLASS];
    NSString *menuName = [NSString stringWithUTF8String:SB_CFG_MENU_CLASS];

    Class auth = NSClassFromString(authName);
    if (!auth) {
        SBLog(@"授权类 %@ 未加载（稍后重试）", authName);
    } else {
        int n = SB_hookBoolMethods(auth);
        SBLog(@"授权类布尔方法接管 %d 个", n);

        SEL cb = NSSelectorFromString(@"hV8nD3sJ:success:message:expiry:");
        if (SB_hookInstance(auth, cb, (IMP)SB_resultCallback)) {
            SBLog(@"结果回调已接管（保留原链）");
        }
    }

    Class menu = NSClassFromString(menuName);
    if (menu) {
        int n = SB_hookBoolMethods(menu);
        SBLog(@"菜单类布尔方法接管 %d 个", n);

        SEL st = NSSelectorFromString(@"updateStatusText:");
        if (SB_hookInstance(menu, st, (IMP)SB_statusText)) {
            SBLog(@"状态文案已接管（保留原链）");
        }
    } else {
        SBLog(@"菜单类 %@ 未加载（稍后重试）", menuName);
    }

    SB_persistAuthorized(nil, nil);
    SBLog(@"本地授权状态已写入");
}
