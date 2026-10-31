// 01-shared.m — 侦察版公共层实现
#import "01-shared.h"
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>
#include <stdarg.h>
#include <stdlib.h>

#pragma mark - 日志落盘

static char g_logPath[1024] = {0};
static FILE *g_logFile = NULL;
static size_t g_written = 0;
static volatile int g_logLock = 0;
static BOOL g_logFull = NO;

// 内存日志：给应用内 UI 面板读取，避免频繁读文件
static NSMutableString *g_memLog = nil;
#define RC_MEM_MAX 300000

static void rc_lock(void) { while (__sync_lock_test_and_set(&g_logLock, 1)) {} }
static void rc_unlock(void) { __sync_lock_release(&g_logLock); }

// 候选路径：越狱全局目录优先，其次沙盒（可用 Filza / 文件 App 取）
static const char *rc_firstWritable(const char **cands, int n) {
    for (int i = 0; i < n; i++) {
        FILE *f = fopen(cands[i], "a");
        if (f) {
            fclose(f);
            return cands[i];
        }
    }
    return NULL;
}

BOOL RCOpenLog(void) {
    if (g_logFile) return YES;

    NSString *name = [NSString stringWithUTF8String:RC_CFG_LOG_NAME];
    NSString *home = NSHomeDirectory();

    NSString *p1 = [@"/var/mobile/Documents" stringByAppendingPathComponent:name];
    NSString *p2 = [home stringByAppendingPathComponent:
                    [@"Documents" stringByAppendingPathComponent:name]];
    NSString *p3 = [NSTemporaryDirectory() stringByAppendingPathComponent:name];

    const char *cands[3] = {
        [p1 UTF8String], [p2 UTF8String], [p3 UTF8String]
    };

    // Documents 目录可能不存在，先建
    [[NSFileManager defaultManager] createDirectoryAtPath:
        [home stringByAppendingPathComponent:@"Documents"]
        withIntermediateDirectories:YES attributes:nil error:NULL];

    const char *ok = rc_firstWritable(cands, 3);
    if (!ok) return NO;

    strncpy(g_logPath, ok, sizeof(g_logPath) - 1);
    g_logFile = fopen(g_logPath, "a");
    if (!g_logFile) return NO;

    // 记录已有大小，用于上限判断
    fseek(g_logFile, 0, SEEK_END);
    g_written = (size_t)ftell(g_logFile);

    return YES;
}

NSString *RCLogPath(void) {
    if (!g_logPath[0]) return nil;
    return [NSString stringWithUTF8String:g_logPath];
}

void RCFlush(void) {
    rc_lock();
    if (g_logFile) fflush(g_logFile);
    rc_unlock();
}

static NSString *rc_timestamp(void) {
    static NSDateFormatter *fmt = nil;
    static RCOnce once;
    // 走 RCDoOnce（内部 dlsym），避免 _dispatch_once 静态绑定
    RCDoOnce(&once, ^{
        fmt = [[NSDateFormatter alloc] init];
        [fmt setDateFormat:@"HH:mm:ss.SSS"];
    });
    return [fmt stringFromDate:[NSDate date]];
}

void RCLog(NSString *fmt, ...) {
    if (!fmt) return;

    va_list ap;
    va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    if (!msg) return;

    NSString *line = [NSString stringWithFormat:@"[%@] %@\n",
                      rc_timestamp(), msg];

    // NSLog：dlsym 取得，避免 flat namespace 绑定
    typedef void (*PFN_NSLog)(NSString *, ...);
    static PFN_NSLog p_log = NULL;
    static int done = 0;
    if (!done) { p_log = (PFN_NSLog)RCSym("NSLog"); done = 1; }
    if (p_log) p_log(@"[Recon] %@", msg);

    // 落盘 + 内存副本
    rc_lock();
    {
        if (!g_memLog) g_memLog = [NSMutableString string];
        [g_memLog appendString:line];
        NSUInteger over = g_memLog.length;
        if (over > RC_MEM_MAX) {
            [g_memLog deleteCharactersInRange:
                NSMakeRange(0, over - RC_MEM_MAX)];
        }
    }
    if (g_logFile && !g_logFull) {
        NSData *d = [line dataUsingEncoding:NSUTF8StringEncoding];
        if (d && d.length) {
            if (g_written + d.length > RC_CFG_LOG_MAX) {
                g_logFull = YES;
                const char *tail = "\n[Recon] ==== 日志达到上限，停止写入 ====\n";
                fwrite(tail, 1, strlen(tail), g_logFile);
            } else {
                fwrite(d.bytes, 1, d.length, g_logFile);
                g_written += d.length;
            }
            fflush(g_logFile);
        }
    }
    rc_unlock();
}

NSString *RCMemLogSnapshot(void) {
    NSString *copy = nil;
    rc_lock();
    copy = g_memLog ? [g_memLog copy] : @"";
    rc_unlock();
    return copy ? copy : @"";
}

void RCMemLogClear(void) {
    rc_lock();
    g_memLog = [NSMutableString string];
    if (g_logFile) {
        fclose(g_logFile);
        g_logFile = fopen(g_logPath, "w");
        g_written = 0;
        g_logFull = NO;
    }
    rc_unlock();
}

void RCSection(NSString *title) {
    RC(@"──────────────── %@ ────────────────", title);
}

#pragma mark - dlsym

void *RCSym(const char *name) {
    if (!name) return NULL;
    return dlsym(RTLD_DEFAULT, name);
}

#pragma mark - 原函数表

#define RC_SLOT_MAX 256

typedef struct {
    char owner[56];
    char name[88];
    IMP imp;
    int used;
} RC_Slot;

static RC_Slot g_slots[RC_SLOT_MAX];
static volatile int g_slotLock = 0;

static void rc_copy(char *dst, size_t cap, const char *src) {
    if (!dst || cap == 0) return;
    if (!src) { dst[0] = '\0'; return; }
    size_t n = strlen(src);
    if (n >= cap) n = cap - 1;
    memcpy(dst, src, n);
    dst[n] = '\0';
}

void RCStoreIMP(NSString *owner, NSString *name, IMP imp) {
    if (!imp) return;
    const char *o = [owner UTF8String] ?: "";
    const char *n = [name UTF8String] ?: "";

    while (__sync_lock_test_and_set(&g_slotLock, 1)) {}
    for (int i = 0; i < RC_SLOT_MAX; i++) {
        if (!g_slots[i].used) continue;
        if (strcmp(g_slots[i].owner, o) == 0 && strcmp(g_slots[i].name, n) == 0) {
            __sync_lock_release(&g_slotLock);
            return;
        }
    }
    for (int i = 0; i < RC_SLOT_MAX; i++) {
        if (g_slots[i].used) continue;
        rc_copy(g_slots[i].owner, sizeof(g_slots[i].owner), o);
        rc_copy(g_slots[i].name, sizeof(g_slots[i].name), n);
        g_slots[i].imp = imp;
        g_slots[i].used = 1;
        break;
    }
    __sync_lock_release(&g_slotLock);
}

IMP RCOrigIMP(NSString *owner, NSString *name) {
    const char *o = [owner UTF8String] ?: "";
    const char *n = [name UTF8String] ?: "";
    IMP r = NULL;

    while (__sync_lock_test_and_set(&g_slotLock, 1)) {}
    for (int i = 0; i < RC_SLOT_MAX; i++) {
        if (!g_slots[i].used) continue;
        if (strcmp(g_slots[i].owner, o) == 0 && strcmp(g_slots[i].name, n) == 0) {
            r = g_slots[i].imp;
            break;
        }
    }
    __sync_lock_release(&g_slotLock);
    return r;
}

BOOL RCHookInstance(Class cls, SEL sel, IMP replacement) {
    if (!cls || !sel || !replacement) return NO;
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return NO;

    RCStoreIMP(NSStringFromClass(cls), NSStringFromSelector(sel),
               method_getImplementation(m));
    class_replaceMethod(cls, sel, replacement, method_getTypeEncoding(m));
    RC(@"hook -[%@ %@]", NSStringFromClass(cls), NSStringFromSelector(sel));
    return YES;
}

BOOL RCHookClass(Class cls, SEL sel, IMP replacement) {
    if (!cls || !sel || !replacement) return NO;
    Method m = class_getClassMethod(cls, sel);
    if (!m) return NO;

    RCStoreIMP([NSString stringWithFormat:@"+%@", NSStringFromClass(cls)],
               NSStringFromSelector(sel), method_getImplementation(m));
    class_replaceMethod(object_getClass(cls), sel, replacement,
                        method_getTypeEncoding(m));
    RC(@"hook +[%@ %@]", NSStringFromClass(cls), NSStringFromSelector(sel));
    return YES;
}

#pragma mark - 工具

NSString *RCDataToText(NSData *data) {
    if (!data || data.length == 0) return @"(空)";

    NSString *s = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (s) {
        if (s.length > RC_CFG_BODY_MAX) {
            return [[s substringToIndex:RC_CFG_BODY_MAX]
                    stringByAppendingString:@"...(截断)"];
        }
        // 尝试格式化 JSON，便于阅读
        NSString *trim = [s stringByTrimmingCharactersInSet:
                          [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trim.length && ([trim hasPrefix:@"{"] || [trim hasPrefix:@"["])) {
            id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
            if (obj) {
                NSData *pretty = [NSJSONSerialization dataWithJSONObject:obj
                                    options:NSJSONWritingPrettyPrinted error:NULL];
                if (pretty) {
                    NSString *ps = [[NSString alloc] initWithData:pretty
                                    encoding:NSUTF8StringEncoding];
                    if (ps) {
                        if (ps.length > RC_CFG_BODY_MAX) {
                            ps = [[ps substringToIndex:RC_CFG_BODY_MAX]
                                  stringByAppendingString:@"...(截断)"];
                        }
                        return ps;
                    }
                }
            }
        }
        return s;
    }

    // 二进制：base64 前 512 字节
    NSUInteger n = data.length > 512 ? 512 : data.length;
    NSData *head = [data subdataWithRange:NSMakeRange(0, n)];
    return [NSString stringWithFormat:@"(二进制 %lu 字节) %@",
            (unsigned long)data.length,
            [head base64EncodedStringWithOptions:0]];
}

NSString *RCDescribe(id obj) {
    if (!obj) return @"(nil)";
    @try {
        if ([obj isKindOfClass:[NSString class]]) return obj;
        if ([obj isKindOfClass:[NSNumber class]]) return [obj stringValue];
        if ([obj isKindOfClass:[NSData class]]) return RCDataToText(obj);
        return [obj description];
    } @catch (...) {
        return @"(不可读)";
    }
}

NSArray *RCCallStack(NSUInteger depth) {
    @try {
        NSArray *s = [[NSThread currentThread] callStackSymbols];
        if (!s) return @[];
        if (s.count <= depth) return s;
        return [s subarrayWithRange:NSMakeRange(0, depth)];
    } @catch (...) {
        return @[];
    }
}

#pragma mark - dispatch

RCQueue RCMainQueue(void) {
    typedef RCQueue (*PFN)(void);
    static PFN fn = NULL;
    static int done = 0;
    if (!done) { fn = (PFN)RCSym("dispatch_get_main_queue"); done = 1; }
    return fn ? fn() : (RCQueue)0;
}

void RCAsyncMain(void (^blk)(void)) {
    typedef void (*PFN)(RCQueue, void (^)(void));
    static PFN fn = NULL;
    static int done = 0;
    if (!done) { fn = (PFN)RCSym("dispatch_async"); done = 1; }
    if (!fn || !blk) return;
    fn(RCMainQueue(), blk);
}

void RCAfterSec(double sec, void (^blk)(void)) {
    typedef RCTime (*PFN_TIME)(RCTime, int64_t);
    typedef void (*PFN_AFTER)(RCTime, RCQueue, void (^)(void));
    static PFN_TIME p_time = NULL;
    static PFN_AFTER p_after = NULL;
    static int done = 0;
    if (!done) {
        p_time = (PFN_TIME)RCSym("dispatch_time");
        p_after = (PFN_AFTER)RCSym("dispatch_after");
        done = 1;
    }
    if (!p_time || !p_after || !blk) return;
    RCTime t = p_time((RCTime)0, (int64_t)(sec * 1e9));
    p_after(t, RCMainQueue(), blk);
}

void RCDoOnce(RCOnce *pred, void (^blk)(void)) {
    typedef void (*PFN)(RCOnce *, void (^)(void));
    static PFN fn = NULL;
    static int done = 0;
    if (!done) { fn = (PFN)RCSym("dispatch_once"); done = 1; }
    if (fn && pred && blk) fn(pred, blk);
}
