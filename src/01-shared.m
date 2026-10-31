// 01-shared.m — 公共基础层实现
#import "01-shared.h"
#include <dlfcn.h>
#include <string.h>
#include <stdarg.h>

#pragma mark - 配置

// 全部取自 00-config.h，代码里不写死数值
static const char *kMasterCard  = SB_CFG_MASTER_CARD;
static const BOOL  kAcceptAny   = (SB_CFG_ACCEPT_ANY != 0);
static const BOOL  kOverride    = (SB_CFG_OVERRIDE_FAILURE_TEXT != 0);

const char *SB_masterCardC(void) { return kMasterCard; }
NSString *SB_masterCard(void) { return [NSString stringWithUTF8String:kMasterCard]; }
BOOL SB_acceptAny(void) { return kAcceptAny; }
BOOL SB_overrideFailureText(void) { return kOverride; }

#pragma mark - dlsym

void *SB_sym(const char *name) {
    if (!name) return NULL;
    return dlsym(RTLD_DEFAULT, name);
}

#pragma mark - 日志

void SBLogLine(NSString *fmt, ...) {
    if (!fmt) return;

    va_list ap;
    va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    if (!msg) return;

    NSString *line = [NSString stringWithFormat:@"[StarBypass] %@", msg];

    typedef void (*PFN_NSLog)(NSString *, ...);
    static PFN_NSLog p_log = NULL;
    static int done = 0;
    if (!done) {
        p_log = (PFN_NSLog)SB_sym("NSLog");
        done = 1;
    }
    if (p_log) p_log(@"%@", line);
}

#pragma mark - 原函数表

#define SB_SLOT_MAX 192

typedef struct {
    char owner[56];
    char name[88];
    IMP  imp;
    int  used;
} SB_Slot;

static SB_Slot g_slots[SB_SLOT_MAX];
static volatile int g_slotLock = 0;

static void sb_lock(void) {
    while (__sync_lock_test_and_set(&g_slotLock, 1)) { }
}
static void sb_unlock(void) { __sync_lock_release(&g_slotLock); }

static void sb_copy(char *dst, size_t cap, const char *src) {
    if (!dst || cap == 0) return;
    if (!src) { dst[0] = '\0'; return; }
    size_t n = strlen(src);
    if (n >= cap) n = cap - 1;
    memcpy(dst, src, n);
    dst[n] = '\0';
}

void SB_storeIMP(NSString *owner, NSString *name, IMP imp) {
    if (!imp) return;
    const char *o = [owner UTF8String] ?: "";
    const char *n = [name UTF8String] ?: "";

    sb_lock();
    // 已存在则不覆盖，保留最初的原始实现
    for (int i = 0; i < SB_SLOT_MAX; i++) {
        if (!g_slots[i].used) continue;
        if (strcmp(g_slots[i].owner, o) == 0 && strcmp(g_slots[i].name, n) == 0) {
            sb_unlock();
            return;
        }
    }
    for (int i = 0; i < SB_SLOT_MAX; i++) {
        if (g_slots[i].used) continue;
        sb_copy(g_slots[i].owner, sizeof(g_slots[i].owner), o);
        sb_copy(g_slots[i].name, sizeof(g_slots[i].name), n);
        g_slots[i].imp = imp;
        g_slots[i].used = 1;
        break;
    }
    sb_unlock();
}

IMP SB_origIMP(NSString *owner, NSString *name) {
    const char *o = [owner UTF8String] ?: "";
    const char *n = [name UTF8String] ?: "";
    IMP r = NULL;

    sb_lock();
    for (int i = 0; i < SB_SLOT_MAX; i++) {
        if (!g_slots[i].used) continue;
        if (strcmp(g_slots[i].owner, o) == 0 && strcmp(g_slots[i].name, n) == 0) {
            r = g_slots[i].imp;
            break;
        }
    }
    sb_unlock();
    return r;
}

#pragma mark - hook 封装

BOOL SB_hookInstance(Class cls, SEL sel, IMP replacement) {
    if (!cls || !sel || !replacement) return NO;

    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return NO;

    IMP orig = method_getImplementation(m);
    NSString *owner = NSStringFromClass(cls);
    NSString *name = NSStringFromSelector(sel);
    SB_storeIMP(owner, name, orig);

    class_replaceMethod(cls, sel, replacement, method_getTypeEncoding(m));
    SBLog(@"hook -[%@ %@]", owner, name);
    return YES;
}

BOOL SB_hookClass(Class cls, SEL sel, IMP replacement) {
    if (!cls || !sel || !replacement) return NO;

    Method m = class_getClassMethod(cls, sel);
    if (!m) return NO;

    IMP orig = method_getImplementation(m);
    NSString *owner = [NSString stringWithFormat:@"+%@", NSStringFromClass(cls)];
    NSString *name = NSStringFromSelector(sel);
    SB_storeIMP(owner, name, orig);

    class_replaceMethod(object_getClass(cls), sel, replacement, method_getTypeEncoding(m));
    SBLog(@"hook +[%@ %@]", NSStringFromClass(cls), name);
    return YES;
}

#pragma mark - 本地授权状态

void SB_persistAuthorized(NSString *card, NSString *expiry) {
    NSString *exp = expiry ? expiry : [NSString stringWithUTF8String:SB_CFG_EXPIRY];
    NSString *c = card ? card : SB_masterCard();

    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    if (!ud) return;

    // 布尔类
    for (NSString *k in @[@"activationState", @"isActivated", @"activated",
                          @"isVip", @"isVIP", @"vip", @"isMember", @"member",
                          @"authorized", @"isAuthorized", @"licensed", @"isLicensed",
                          @"isPaid", @"paid", @"isPro", @"pro"]) {
        [ud setBool:YES forKey:k];
    }

    // 时间类
    for (NSString *k in @[@"expiry", @"expire", @"expireTime", @"expireDate",
                          @"endTime", @"end_time", @"deadline", @"validUntil"]) {
        [ud setObject:exp forKey:k];
    }

    // 卡密类
    for (NSString *k in @[@"card", @"kami", @"license", @"licence",
                          @"cardNo", @"card_no", @"code", @"authcode"]) {
        [ud setObject:c forKey:k];
    }

    // 等级类
    [ud setObject:@"VIP" forKey:@"userLevel"];
    [ud setObject:@"VIP" forKey:@"vipLevel"];
    [ud setInteger:99 forKey:@"level"];
    [ud setInteger:99 forKey:@"vip_level"];
    [ud setInteger:1 forKey:@"status"];
    [ud setInteger:1 forKey:@"state"];
    [ud setInteger:1 forKey:@"type"];

    [ud synchronize];
}

BOOL SB_localAuthorized(void) {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    if (!ud) return YES;   // 取不到就默认放行，避免误判

    for (NSString *k in @[@"activationState", @"isActivated", @"isVip",
                          @"isVIP", @"isMember", @"authorized", @"isAuthorized"]) {
        if ([ud boolForKey:k]) return YES;
    }
    return NO;
}

#pragma mark - dispatch 封装

SBQueue SB_mainQueue(void) {
    typedef SBQueue (*PFN)(void);
    static PFN fn = NULL;
    static int done = 0;
    if (!done) { fn = (PFN)SB_sym("dispatch_get_main_queue"); done = 1; }
    return fn ? fn() : (SBQueue)0;
}

void SB_asyncMain(void (^blk)(void)) {
    typedef void (*PFN)(SBQueue, void (^)(void));
    static PFN fn = NULL;
    static int done = 0;
    if (!done) { fn = (PFN)SB_sym("dispatch_async"); done = 1; }
    if (!fn || !blk) return;
    fn(SB_mainQueue(), blk);
}

void SB_afterSec(double sec, void (^blk)(void)) {
    typedef SBTime (*PFN_TIME)(SBTime, int64_t);
    typedef void (*PFN_AFTER)(SBTime, SBQueue, void (^)(void));
    static PFN_TIME p_time = NULL;
    static PFN_AFTER p_after = NULL;
    static int done = 0;
    if (!done) {
        p_time = (PFN_TIME)SB_sym("dispatch_time");
        p_after = (PFN_AFTER)SB_sym("dispatch_after");
        done = 1;
    }
    if (!p_time || !p_after || !blk) return;
    SBTime t = p_time((SBTime)0, (int64_t)(sec * 1e9));
    p_after(t, SB_mainQueue(), blk);
}

void SB_once(SBOnce *pred, void (^blk)(void)) {
    typedef void (*PFN)(SBOnce *, void (^)(void));
    static PFN fn = NULL;
    static int done = 0;
    if (!done) { fn = (PFN)SB_sym("dispatch_once"); done = 1; }
    if (fn && pred && blk) fn(pred, blk);
}

#pragma mark - 卡密判定

BOOL SB_isMaster(id obj) {
    if (!obj) return NO;

    NSString *s = nil;
    if ([obj isKindOfClass:[NSString class]]) {
        s = obj;
    } else if ([obj respondsToSelector:@selector(stringValue)]) {
        s = [obj stringValue];
    }
    if (!s) return NO;

    NSString *t = [[s stringByTrimmingCharactersInSet:
                    [NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    return [t isEqualToString:[SB_masterCard() lowercaseString]];
}
