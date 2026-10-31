// 03-trace.m — 授权类方法追踪
//
// 先 dump 全量方法表（含类型编码），这是阶段二改代码最需要的数据。
// 再对可安全包装的方法加观测：只记录，不改返回值、不改参数。
//
// 安全策略：
//   1. 每个方法用 imp_implementationWithBlock 生成独立包装，
//      不用全局槽位表 —— 避免不同类同名选择器互相踩（会调到错误实现上崩掉）。
//   2. 只包装返回 BOOL / void 且参数 ≤1 的方法，调用约定可控。
//   3. 一个已知 4 参方法单独用精确签名包装。
//   4. 其余类型不碰。

#import "01-shared.h"
#include <stdlib.h>
#include <string.h>

#pragma mark - 方法表 dump

static void rc_dumpMethods(Class cls, BOOL classSide) {
    if (!cls) return;

    Class target = classSide ? object_getClass(cls) : cls;
    unsigned int count = 0;
    Method *list = class_copyMethodList(target, &count);
    if (!list) {
        RC(@"  %@ 方法表读取失败", NSStringFromClass(cls));
        return;
    }

    RC(@"%c[%@] 共 %u 个方法",
       classSide ? '+' : '-', NSStringFromClass(cls), count);

    for (unsigned int i = 0; i < count; i++) {
        SEL sel = method_getName(list[i]);
        const char *enc = method_getTypeEncoding(list[i]);
        unsigned int nargs = method_getNumberOfArguments(list[i]);
        RC(@"   %c[%@ %@] enc=%s args=%u",
           classSide ? '+' : '-',
           NSStringFromClass(cls),
           NSStringFromSelector(sel),
           enc ? enc : "?",
           nargs);
    }
    free(list);
}

#pragma mark - 观测包装

static const char *rc_retName(char r) {
    return (r == 'v') ? "void" : "BOOL";
}

// 返回 BOOL、0 参
static void rc_wrapBool0(Class cls, Method m, NSString *name) {
    IMP orig = method_getImplementation(m);
    const char *enc = method_getTypeEncoding(m);

    IMP nb = imp_implementationWithBlock(^BOOL(id self) {
        BOOL r = ((BOOL (*)(id, SEL))orig)(self, NSSelectorFromString(name));
        RC(@"   ← %@ = %@", name, r ? @"YES" : @"NO");
        return r;
    });
    class_replaceMethod(cls, method_getName(m), nb, enc);
}

// 返回 BOOL、1 参
static void rc_wrapBool1(Class cls, Method m, NSString *name) {
    IMP orig = method_getImplementation(m);
    const char *enc = method_getTypeEncoding(m);

    IMP nb = imp_implementationWithBlock(^BOOL(id self, id a) {
        RC(@"   → %@ %@", name, RCDescribe(a));
        BOOL r = ((BOOL (*)(id, SEL, id))orig)(self, NSSelectorFromString(name), a);
        RC(@"   ← %@ = %@", name, r ? @"YES" : @"NO");
        return r;
    });
    class_replaceMethod(cls, method_getName(m), nb, enc);
}

// 返回 void、0 参
static void rc_wrapVoid0(Class cls, Method m, NSString *name) {
    IMP orig = method_getImplementation(m);
    const char *enc = method_getTypeEncoding(m);

    IMP nb = imp_implementationWithBlock(^(id self) {
        RC(@"   → %@", name);
        ((void (*)(id, SEL))orig)(self, NSSelectorFromString(name));
    });
    class_replaceMethod(cls, method_getName(m), nb, enc);
}

// 返回 void、1 参
static void rc_wrapVoid1(Class cls, Method m, NSString *name) {
    IMP orig = method_getImplementation(m);
    const char *enc = method_getTypeEncoding(m);

    IMP nb = imp_implementationWithBlock(^(id self, id a) {
        RC(@"   → %@ %@", name, RCDescribe(a));
        ((void (*)(id, SEL, id))orig)(self, NSSelectorFromString(name), a);
    });
    class_replaceMethod(cls, method_getName(m), nb, enc);
}

// 已知 4 参：-hV8nD3sJ:success:message:expiry:
typedef void (*PFN_RESULT)(id, SEL, id, BOOL, id, id);

static void rc_wrapResult(Class cls, Method m) {
    IMP orig = method_getImplementation(m);
    const char *enc = method_getTypeEncoding(m);
    NSString *name = NSStringFromSelector(method_getName(m));

    IMP nb = imp_implementationWithBlock(^(id self, id a, BOOL ok, id msg, id exp) {
        RC(@"   ★ %@ success=%d message=%@ expiry=%@",
           name, (int)ok, RCDescribe(msg), RCDescribe(exp));
        ((PFN_RESULT)orig)(self, NSSelectorFromString(name), a, ok, msg, exp);
    });
    class_replaceMethod(cls, method_getName(m), nb, enc);
}

#pragma mark - 安装

static int rc_traceClass(Class cls) {
    if (!cls) return 0;

    unsigned int count = 0;
    Method *list = class_copyMethodList(cls, &count);
    if (!list) return 0;

    int wrapped = 0;
    for (unsigned int i = 0; i < count; i++) {
        Method m = list[i];
        SEL sel = method_getName(m);
        const char *enc = method_getTypeEncoding(m);
        if (!enc || !enc[0]) continue;

        char ret = enc[0];
        unsigned int nargs = method_getNumberOfArguments(m);
        unsigned int params = nargs >= 2 ? nargs - 2 : 0;

        if ((ret != 'B' && ret != 'c' && ret != 'v') || params > 1) continue;

        NSString *name = NSStringFromSelector(sel);

        if (ret == 'v') {
            if (params == 0) rc_wrapVoid0(cls, m, name);
            else rc_wrapVoid1(cls, m, name);
        } else {
            if (params == 0) rc_wrapBool0(cls, m, name);
            else rc_wrapBool1(cls, m, name);
        }
        RC(@"   观测 %c[%@ %@] (%s/%u参)",
           '-', NSStringFromClass(cls), name, rc_retName(ret), params);
        wrapped++;
    }
    free(list);

    // 精确签名方法
    SEL sel = NSSelectorFromString(@"hV8nD3sJ:success:message:expiry:");
    Method m = class_getInstanceMethod(cls, sel);
    if (m) {
        rc_wrapResult(cls, m);
        RC(@"   观测 -[%@ %@] (精确签名)",
           NSStringFromClass(cls), NSStringFromSelector(sel));
        wrapped++;
    }
    return wrapped;
}

void RCInstallTrace(void) {
    RCSection(@"授权类方法表");

    NSString *authName = [NSString stringWithUTF8String:RC_CFG_AUTH_CLASS];
    NSString *menuName = [NSString stringWithUTF8String:RC_CFG_MENU_CLASS];

    Class auth = NSClassFromString(authName);
    if (!auth) {
        RC(@"授权类 %@ 未加载", authName);
    } else {
        rc_dumpMethods(auth, NO);
        rc_dumpMethods(auth, YES);
        RCSection(@"授权类观测");
        RC(@"授权类观测挂载 %d 个", rc_traceClass(auth));
    }

    Class menu = NSClassFromString(menuName);
    if (!menu) {
        RC(@"菜单类 %@ 未加载", menuName);
    } else {
        RCSection(@"菜单类观测");
        RC(@"菜单类观测挂载 %d 个", rc_traceClass(menu));
    }
}
