// 05-stealth.m — 检测绕过
//
// 目标：让被注入的 app 认为环境干净，行为与未注入时一致。
// 否则它可能检测到注入模块直接拒绝运行，我们就抓不到东西。
//
// 逆向确认原 dylib 导入了这些探测点：
//   CFNetworkCopySystemProxySettings  代理探测
//   getifaddrs                        VPN 网卡枚举
//   fopen                             文件探测
//   statfs                            文件系统探测
//   _dyld_get_image_name              注入模块枚举
//
// 注意：本模块不用于"抓包工具绕过"，而是保证侦察 dylib 自身不被发现。
// 我们直接在进程内读明文，不需要代理，所以不会触发代理检测路径。

#import "01-shared.h"
#import "symbol-rebind.h"
#include <dlfcn.h>
#include <string.h>
#include <stdio.h>
#include <sys/mount.h>
#include <sys/statfs.h>
#include <ifaddrs.h>
#include <net/if.h>

#pragma mark - 名单

// 需要从模块枚举里隐藏的名字（含我们自己）
static const char *kHideModules[] = {
    "ReconDylib", "StarRecon", "StarBypass",
    "FridaGadget", "frida", "cycript", "SSLKillSwitch",
    "libhooker", "substitute", "ellekit", "RocketBootstrap",
    "Choicy", "AppSync", "TweakInject",
};

static const char *kBadPaths[] = {
    "/usr/sbin/frida-server", "/usr/lib/frida", "/var/jb",
    "/Applications/Cydia.app", "/bin/bash", "/usr/bin/ssh",
    "/etc/apt", "/usr/libexec/cydia",
    "frida", "cycript", "ReconDylib", "StarRecon",
};

static BOOL rc_matchAny(const char *s, const char **list, size_t n) {
    if (!s) return NO;
    for (size_t i = 0; i < n; i++) {
        if (strcasestr(s, list[i])) return YES;
    }
    return NO;
}

static BOOL rc_isVpnName(const char *n) {
    if (!n) return NO;
    return (strncmp(n, "utun", 4) == 0) ||
           (strncmp(n, "ppp", 3) == 0) ||
           (strncmp(n, "ipsec", 5) == 0) ||
           (strncmp(n, "tun", 3) == 0) ||
           (strncmp(n, "tap", 3) == 0);
}

#pragma mark - 代理

typedef CFDictionaryRef (*PFN_PROXY)(void);

static CFDictionaryRef rc_copyProxy(void) {
    NSDictionary *empty = @{
        @"HTTPEnable": @0,
        @"HTTPSEnable": @0,
        @"SOCKSEnable": @0,
        @"ProxyAutoConfigEnable": @0,
        @"ProxyAutoDiscoveryEnable": @0,
        @"ExceptionsList": @[],
    };
    return (CFDictionaryRef)CFRetain((__bridge CFDictionaryRef)empty);
}

#pragma mark - 模块枚举

typedef const char *(*PFN_IMGNAME)(uint32_t);

static const char *rc_imageName(uint32_t idx) {
    static PFN_IMGNAME orig = NULL;
    static int done = 0;
    if (!done) { orig = (PFN_IMGNAME)RCSym("_dyld_get_image_name"); done = 1; }
    if (!orig) return NULL;

    const char *n = orig(idx);
    if (!n) return n;

    if (rc_matchAny(n, kHideModules,
                    sizeof(kHideModules) / sizeof(kHideModules[0]))) {
        // 用正常模块名顶替，保持枚举数量不变
        return "UIKit";
    }
    return n;
}

#pragma mark - 文件系统

typedef int (*PFN_STATFS)(const char *, struct statfs *);

static int rc_statfs(const char *path, struct statfs *buf) {
    static PFN_STATFS orig = NULL;
    static int done = 0;
    if (!done) { orig = (PFN_STATFS)RCSym("statfs"); done = 1; }
    if (!orig) return -1;

    int r = orig(path, buf);
    if (buf) {
        memset(buf->f_fstypename, 0, sizeof(buf->f_fstypename));
        strncpy(buf->f_fstypename, "apfs", sizeof(buf->f_fstypename) - 1);
        buf->f_flags = 0;
    }
    return r;
}

typedef FILE *(*PFN_FOPEN)(const char *, const char *);

static FILE *rc_fopen(const char *path, const char *mode) {
    static PFN_FOPEN orig = NULL;
    static int done = 0;
    if (!done) { orig = (PFN_FOPEN)RCSym("fopen"); done = 1; }
    if (!orig) return NULL;

    if (path && rc_matchAny(path, kBadPaths,
                            sizeof(kBadPaths) / sizeof(kBadPaths[0]))) {
        RC(@"[stealth] 屏蔽文件探测: %s", path);
        return NULL;
    }
    return orig(path, mode);
}

#pragma mark - 网卡

typedef int (*PFN_IFA)(struct ifaddrs **);

static int rc_getifaddrs(struct ifaddrs **ifap) {
    static PFN_IFA orig = NULL;
    static int done = 0;
    if (!done) { orig = (PFN_IFA)RCSym("getifaddrs"); done = 1; }
    if (!orig || !ifap) return -1;

    int r = orig(ifap);
    if (r != 0 || !*ifap) return r;

    struct ifaddrs *head = *ifap;
    struct ifaddrs *prev = NULL;
    struct ifaddrs *cur = head;

    while (cur) {
        struct ifaddrs *next = cur->ifa_next;
        if (rc_isVpnName(cur->ifa_name)) {
            RC(@"[stealth] 隐藏网卡: %s", cur->ifa_name);
            if (prev) prev->ifa_next = next;
            else head = next;
            cur->ifa_next = NULL;   // 只摘链，不释放
        } else {
            prev = cur;
        }
        cur = next;
    }
    *ifap = head;
    return r;
}

#pragma mark - 安装

void RCInstallStealth(void) {
    RCSection(@"检测绕过");

    struct sb_rebinding rb[] = {
        { "CFNetworkCopySystemProxySettings", (void *)rc_copyProxy,  NULL },
        { "getifaddrs",                       (void *)rc_getifaddrs, NULL },
        { "fopen",                            (void *)rc_fopen,      NULL },
        { "statfs",                           (void *)rc_statfs,     NULL },
        { "_dyld_get_image_name",             (void *)rc_imageName,  NULL },
    };
    int n = (int)(sizeof(rb) / sizeof(rb[0]));
    int r = SB_rebind_symbols(rb, (size_t)n);
    RC(@"符号替换 %d 项，结果 %d", n, r);
}
