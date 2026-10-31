// 05-detection.m — 对抗层：绕过 VPN / 代理 / 抓包 / 越狱检测
//
// 原 dylib 导入了这些探测符号（已逆向确认）：
//   CFNetworkCopySystemProxySettings   代理探测
//   getifaddrs                         VPN 网卡枚举
//   fopen                              文件探测
//   statfs / statfs64                  文件系统探测
//   _dyld_get_image_name               注入模块枚举
//
// 全部在符号层替换；原函数用 dlsym 取得并缓存，取不到则安全降级。

#import "01-shared.h"
#import "symbol-rebind.h"
#include <dlfcn.h>
#include <string.h>
#include <stdio.h>
#include <sys/mount.h>
#include <sys/statfs.h>
#include <ifaddrs.h>
#include <net/if.h>

#pragma mark - 可疑名单

static const char *kBadModules[] = {
    "FridaGadget", "frida", "cycript", "SSLKillSwitch", "libhooker",
    "substitute", "ellekit", "HttpCanary", "Charles", "Fiddler",
    "libpcap", "tcpdump", "RocketBootstrap", "StarBypass",
    "Choicy", "AppSync", "TrollFools",
};

static const char *kBadPaths[] = {
    "/usr/sbin/frida-server", "/usr/lib/frida", "/var/jb",
    "/Applications/Cydia.app", "/bin/bash", "/usr/bin/ssh",
    "/etc/apt", "/usr/libexec/cydia",
    "frida", "cycript", "tcpdump", "libpcap", "HttpCanary", "charles",
};

static BOOL SB_matchAny(const char *s, const char **list, size_t n) {
    if (!s) return NO;
    for (size_t i = 0; i < n; i++) {
        if (strcasestr(s, list[i])) return YES;
    }
    return NO;
}

static BOOL SB_isVpnName(const char *n) {
    if (!n) return NO;
    return (strncmp(n, "utun", 4) == 0) ||
           (strncmp(n, "ppp", 3) == 0) ||
           (strncmp(n, "ipsec", 5) == 0) ||
           (strncmp(n, "tun", 3) == 0) ||
           (strncmp(n, "tap", 3) == 0) ||
           (strncmp(n, "wg", 2) == 0);
}

#pragma mark - 代理探测

typedef CFDictionaryRef (*PFN_CopyProxy)(void);

static CFDictionaryRef SB_CopySystemProxySettings(void) {
    SBLog(@"[detect] 代理探测 → 返回空代理");
    return (CFDictionaryRef)CFRetain((__bridge CFDictionaryRef)@{
        @"HTTPEnable": @0,
        @"HTTPSEnable": @0,
        @"SOCKSEnable": @0,
        @"ProxyAutoConfigEnable": @0,
        @"ProxyAutoDiscoveryEnable": @0,
        @"ExceptionsList": @[],
    });
}

#pragma mark - 模块枚举

static const char *SB_dyld_get_image_name(uint32_t idx) {
    typedef const char *(*PFN)(uint32_t);
    static PFN orig = NULL;
    static int done = 0;
    if (!done) { orig = (PFN)SB_sym("_dyld_get_image_name"); done = 1; }

    if (!orig) return NULL;   // 取不到就原样放行，绝不返回误导性空串

    const char *n = orig(idx);
    if (!n) return n;

    if (SB_matchAny(n, kBadModules, sizeof(kBadModules) / sizeof(kBadModules[0]))) {
        // 命中可疑模块，用正常模块名顶替，保持枚举数量不变
        return "UIKit";
    }
    return n;
}

#pragma mark - 文件系统

static int SB_statfs(const char *path, struct statfs *buf) {
    typedef int (*PFN)(const char *, struct statfs *);
    static PFN orig = NULL;
    static int done = 0;
    if (!done) { orig = (PFN)SB_sym("statfs"); done = 1; }

    if (!orig) return -1;
    int r = orig(path, buf);
    if (buf) {
        memset(buf->f_fstypename, 0, sizeof(buf->f_fstypename));
        strncpy(buf->f_fstypename, "apfs", sizeof(buf->f_fstypename) - 1);
        buf->f_flags = 0;
    }
    return r;
}

static FILE *SB_fopen_guard(const char *path, const char *mode) {
    typedef FILE *(*PFN)(const char *, const char *);
    static PFN orig = NULL;
    static int done = 0;
    if (!done) { orig = (PFN)SB_sym("fopen"); done = 1; }

    if (path && SB_matchAny(path, kBadPaths, sizeof(kBadPaths) / sizeof(kBadPaths[0]))) {
        SBLog(@"[detect] 屏蔽文件探测: %s", path);
        return NULL;
    }
    return orig ? orig(path, mode) : NULL;
}

#pragma mark - 网卡枚举

static int SB_getifaddrs_guard(struct ifaddrs **ifap) {
    typedef int (*PFN)(struct ifaddrs **);
    static PFN orig = NULL;
    static int done = 0;
    if (!done) { orig = (PFN)SB_sym("getifaddrs"); done = 1; }

    if (!orig || !ifap) return -1;

    int r = orig(ifap);
    if (r != 0 || !*ifap) return r;

    struct ifaddrs *head = *ifap;
    struct ifaddrs *prev = NULL;
    struct ifaddrs *cur = head;

    while (cur) {
        struct ifaddrs *next = cur->ifa_next;
        if (SB_isVpnName(cur->ifa_name)) {
            SBLog(@"[detect] 隐藏网卡: %s", cur->ifa_name);
            if (prev) prev->ifa_next = next;
            else head = next;
            cur->ifa_next = NULL;   // 只摘链，不释放，避免二次释放
        } else {
            prev = cur;
        }
        cur = next;
    }
    *ifap = head;
    return r;
}

#pragma mark - 安装

void SB_installDetection(void) {
    struct sb_rebinding rb[] = {
        { "CFNetworkCopySystemProxySettings", (void *)SB_CopySystemProxySettings, NULL },
        { "getifaddrs",                       (void *)SB_getifaddrs_guard,        NULL },
        { "fopen",                            (void *)SB_fopen_guard,             NULL },
        { "statfs",                           (void *)SB_statfs,                  NULL },
        { "_dyld_get_image_name",             (void *)SB_dyld_get_image_name,     NULL },
    };

    int n = (int)(sizeof(rb) / sizeof(rb[0]));
    int r = SB_rebind_symbols(rb, (size_t)n);
    SBLog(@"[detect] 符号替换 %d 项，结果 %d", n, r);
}
