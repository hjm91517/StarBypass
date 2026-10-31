// 03-network.m — 网络层：双保险拦截
//
// 逆向确认（assets/FlashBytePro.dylib）：实际只用到两个选择器
//   dataTaskWithRequest:completionHandler:
//   dataTaskWithURL:completionHandler:
// 即 stub 4 类路径中的 block 路径，没有 delegate 路径。
//
// 双保险设计：
//   第一道 NSURLProtocol —— 请求不出设备，返回真实 NSURLResponse 对象
//   第二道 替换 completionHandler —— 即使协议注入失效，也把回包数据换掉
//
// 第二道为什么安全：仍调用原始方法创建真实 task（对象语义、生命周期不变），
// 只把交给 app 的数据换成伪造成功包。不返回假 task，避免 originalRequest 为 nil。

#import "01-shared.h"
#import <UIKit/UIKit.h>
#import <CommonCrypto/CommonDigest.h>
#include <dlfcn.h>
#include <string.h>

#pragma mark - 摘要

static NSString *SB_sha256Hex(NSData *data) {
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    memset(digest, 0, sizeof(digest));

    typedef unsigned char *(*PFN)(const void *, uint32_t, unsigned char *);
    static PFN p_sha = NULL;
    static int done = 0;
    if (!done) { p_sha = (PFN)SB_sym("CC_SHA256"); done = 1; }
    if (p_sha && data && data.length) {
        p_sha(data.bytes, (uint32_t)data.length, digest);
    }

    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
        [hex appendFormat:@"%02x", digest[i]];
    }
    return hex;
}

#pragma mark - 请求解析

static NSDictionary *SB_parseBody(NSData *body) {
    if (!body || body.length == 0) return @{};
    NSString *s = [[NSString alloc] initWithData:body encoding:NSUTF8StringEncoding];
    if (!s) return @{};

    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    NSString *trim = [s stringByTrimmingCharactersInSet:
                      [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trim.length && [trim hasPrefix:@"{"]) {
        id obj = [NSJSONSerialization JSONObjectWithData:
                  [trim dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
        if ([obj isKindOfClass:[NSDictionary class]]) return obj;
        return dict;
    }
    for (NSString *pair in [s componentsSeparatedByString:@"&"]) {
        NSArray *kv = [pair componentsSeparatedByString:@"="];
        if ([kv count] == 2) {
            NSString *raw = (NSString *)[kv objectAtIndex:1];
            NSString *key = (NSString *)[kv objectAtIndex:0];
            NSString *dec = [raw stringByRemovingPercentEncoding];
            [dict setObject:(dec ? dec : raw) forKey:key];
        }
    }
    return dict;
}

static NSString *SB_pick(NSDictionary *p, NSArray *keys) {
    for (NSString *k in keys) {
        id v = [p objectForKey:k];
        if ([v isKindOfClass:[NSString class]] && [(NSString *)v length]) return v;
    }
    return nil;
}

#pragma mark - 判定

BOOL SB_shouldFake(NSURLRequest *req) {
    if (!req) return NO;

    NSString *method = [[req HTTPMethod] uppercaseString];
    NSData *body = [req HTTPBody];
    NSString *url = [[[req URL] absoluteString] lowercaseString];

    SBLog(@"[net] %@ %@ bodyLen=%lu",
          method ? method : @"?",
          url ? url : @"(nil)",
          (unsigned long)(body ? body.length : 0));

    if ([method isEqualToString:@"POST"] && body.length > 0) return YES;
    for (NSString *k in @[@"activ", @"licen", @"card", @"kami", @"cdk",
                          @"auth", @"verif", @"login", @"expire", @"vip"]) {
        if (url && [url containsString:k]) return YES;
    }
    return NO;
}

#pragma mark - 回包构造

NSData *SB_buildSuccessBody(NSURLRequest *req) {
    NSDictionary *params = SB_parseBody([req HTTPBody]);

    NSString *card = SB_pick(params, @[@"code", @"card", @"kami", @"cdk",
                                       @"key", @"license", @"licence", @"authcode"]);
    if (!card) card = SB_masterCard();
    NSString *uuid = SB_pick(params, @[@"uuid", @"device", @"deviceid",
                                       @"udid", @"imei", @"idfa", @"openid"]);
    if (!uuid) uuid = @"00000000-0000-0000-0000-000000000000";
    NSString *expiry = [NSString stringWithUTF8String:SB_CFG_EXPIRY];

    // 客户端用 SHA256 比对签名，三种拼接顺序全给
    NSString *signA = SB_sha256Hex([[NSString stringWithFormat:@"%@%@%@", card, uuid, expiry]
                                    dataUsingEncoding:NSUTF8StringEncoding]);
    NSString *signB = SB_sha256Hex([[NSString stringWithFormat:@"%@%@", card, uuid]
                                    dataUsingEncoding:NSUTF8StringEncoding]);
    NSString *signC = SB_sha256Hex([[NSString stringWithFormat:@"%@", expiry]
                                    dataUsingEncoding:NSUTF8StringEncoding]);

    NSDictionary *inner = @{
        @"code": card, @"card": card, @"kami": card,
        @"uuid": uuid, @"device": uuid,
        @"expiry": expiry, @"expire": expiry, @"expireTime": expiry, @"endTime": expiry,
        @"vip": @YES, @"isVip": @YES, @"vipLevel": @99, @"level": @99,
        @"status": @1, @"state": @1, @"type": @1,
        @"sign": signA, @"checkSign": signA, @"token": signA,
        @"msg": @"激活成功", @"message": @"激活成功",
    };
    NSDictionary *root = @{
        @"code": @200, @"status": @200, @"errcode": @0, @"errno": @0,
        @"success": @YES, @"result": @YES, @"ok": @YES,
        @"msg": @"激活成功", @"message": @"激活成功", @"info": @"激活成功",
        @"expiry": expiry, @"expire": expiry, @"vip": @YES,
        @"sign": signA, @"checkSign": signA, @"token": signA,
        @"signA": signA, @"signB": signB, @"signC": signC,
        @"data": inner, @"result_data": inner, @"info_data": inner,
    };

    SB_persistAuthorized(card, expiry);

    NSData *json = [NSJSONSerialization dataWithJSONObject:root options:0 error:NULL];
    if (json) return json;

    NSString *fb = [NSString stringWithFormat:
        @"{\"code\":200,\"success\":true,\"vip\":true,\"expiry\":\"%@\",\"sign\":\"%@\","
        @"\"data\":{\"code\":\"%@\",\"expiry\":\"%@\",\"vip\":true,\"sign\":\"%@\"}}",
        expiry, signA, card, expiry, signA];
    return [fb dataUsingEncoding:NSUTF8StringEncoding];
}

static NSHTTPURLResponse *SB_buildResponse(NSURL *url, NSUInteger length) {
    return [[NSHTTPURLResponse alloc]
        initWithURL:url ? url : [NSURL URLWithString:@"https://local"]
         statusCode:200
        HTTPVersion:@"HTTP/1.1"
       headerFields:@{
           @"Content-Type": @"application/json; charset=utf-8",
           @"Content-Length": [NSString stringWithFormat:@"%lu", (unsigned long)length],
           @"Server": @"nginx",
       }];
}

#pragma mark - 第一道：NSURLProtocol

static NSString *const kSBHandledKey = @"SBHandled";

@interface SBURLProtocol : NSURLProtocol
@end

@implementation SBURLProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    if (!request) return NO;
    if ([NSURLProtocol propertyForKey:kSBHandledKey inRequest:request]) return NO;
    return SB_shouldFake(request);
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

- (void)startLoading {
    id client = [self client];
    NSURLRequest *req = [self request];
    NSData *body = SB_buildSuccessBody(req);

    SBLog(@"[net] 第一道拦截，返回伪造回包 %lu 字节", (unsigned long)body.length);

    SB_SAFE_BEGIN
        [client URLProtocol:self
          didReceiveResponse:SB_buildResponse([req URL], body.length)
          cacheStoragePolicy:NSURLCacheStorageNotAllowed];
        [client URLProtocol:self didLoadData:body];
        [client URLProtocolDidFinishLoading:self];
    SB_SAFE_END
}

- (void)stopLoading {
}

@end

// 把自定义协议补进 configuration
static void SB_injectProtocol(NSURLSessionConfiguration *config) {
    if (!config) return;
    NSArray *orig = [config protocolClasses];
    NSMutableArray *arr = orig ? [orig mutableCopy] : [NSMutableArray array];
    for (id c in arr) {
        if (c == [SBURLProtocol class]) return;
    }
    [arr addObject:[SBURLProtocol class]];
    [config setProtocolClasses:arr];
}

#pragma mark - 第二道：替换 completionHandler

typedef id (*PFN_TASK_REQ_CB)(id, SEL, NSURLRequest *,
                              void (^)(NSData *, NSURLResponse *, NSError *));
typedef id (*PFN_TASK_URL_CB)(id, SEL, NSURL *,
                              void (^)(NSData *, NSURLResponse *, NSError *));

static id SB_taskRequestCB(id self, SEL _cmd, NSURLRequest *req,
                           void (^handler)(NSData *, NSURLResponse *, NSError *)) {
    static PFN_TASK_REQ_CB orig = NULL;
    static int done = 0;
    if (!done) {
        orig = (PFN_TASK_REQ_CB)SB_origIMP(@"NSURLSession",
                                           @"dataTaskWithRequest:completionHandler:");
        done = 1;
    }
    if (!orig) return nil;

    if (!handler || !SB_shouldFake(req)) {
        return orig(self, _cmd, req, handler);
    }

    // 仍创建真实 task，只替换交给 app 的数据
    void (^wrap)(NSData *, NSURLResponse *, NSError *) =
    ^(NSData *d, NSURLResponse *r, NSError *e) {
        NSData *fake = SB_buildSuccessBody(req);
        SBLog(@"[net] 第二道拦截，替换回包 %lu 字节", (unsigned long)fake.length);
        handler(fake, r ? r : SB_buildResponse([req URL], fake.length), nil);
    };
    return orig(self, _cmd, req, wrap);
}

static id SB_taskURLCB(id self, SEL _cmd, NSURL *url,
                       void (^handler)(NSData *, NSURLResponse *, NSError *)) {
    static PFN_TASK_URL_CB orig = NULL;
    static int done = 0;
    if (!done) {
        orig = (PFN_TASK_URL_CB)SB_origIMP(@"NSURLSession",
                                           @"dataTaskWithURL:completionHandler:");
        done = 1;
    }
    if (!orig) return nil;

    NSURLRequest *req = [NSURLRequest requestWithURL:url];
    if (!handler || !SB_shouldFake(req)) {
        return orig(self, _cmd, url, handler);
    }

    void (^wrap)(NSData *, NSURLResponse *, NSError *) =
    ^(NSData *d, NSURLResponse *r, NSError *e) {
        NSData *fake = SB_buildSuccessBody(req);
        SBLog(@"[net] 第二道拦截，替换回包 %lu 字节", (unsigned long)fake.length);
        handler(fake, r ? r : SB_buildResponse(url, fake.length), nil);
    };
    return orig(self, _cmd, url, wrap);
}

#pragma mark - 安装

void SB_installNetwork(void) {
    [NSURLProtocol registerClass:[SBURLProtocol class]];
    SBLog(@"[net] 第一道：SBURLProtocol 已注册");

    // 协议注入：两个工厂 + getter + session 创建
    Class cfgCls = NSClassFromString(@"NSURLSessionConfiguration");
    if (cfgCls) {
        struct { const char *name; SEL sel; } factories[] = {
            { "defaultSessionConfiguration", @selector(defaultSessionConfiguration) },
            { "ephemeralSessionConfiguration", @selector(ephemeralSessionConfiguration) },
        };
        for (size_t i = 0; i < sizeof(factories) / sizeof(factories[0]); i++) {
            Method m = class_getClassMethod(cfgCls, factories[i].sel);
            if (!m) continue;
            IMP orig = method_getImplementation(m);
            SEL sel = factories[i].sel;
            IMP nb = imp_implementationWithBlock(^id(id _self) {
                NSURLSessionConfiguration *c = ((id (*)(id, SEL))orig)(_self, sel);
                SB_injectProtocol(c);
                return c;
            });
            class_replaceMethod(object_getClass(cfgCls), sel, nb,
                                method_getTypeEncoding(m));
        }

        SEL ps = @selector(protocolClasses);
        Method mp = class_getInstanceMethod(cfgCls, ps);
        if (mp) {
            IMP orig = method_getImplementation(mp);
            IMP nb = imp_implementationWithBlock(^id(id _self) {
                NSArray *a = ((id (*)(id, SEL))orig)(_self, ps);
                NSMutableArray *arr = a ? [a mutableCopy] : [NSMutableArray array];
                BOOL has = NO;
                for (id c in arr) if (c == [SBURLProtocol class]) { has = YES; break; }
                if (!has) [arr addObject:[SBURLProtocol class]];
                return arr;
            });
            class_replaceMethod(cfgCls, ps, nb, method_getTypeEncoding(mp));
        }
        SBLog(@"[net] 第一道：configuration 注入就位");
    }

    // 第二道
    Class sess = NSClassFromString(@"NSURLSession");
    if (sess) {
        if (SB_hookInstance(sess, @selector(dataTaskWithRequest:completionHandler:),
                            (IMP)SB_taskRequestCB)) {
            SBLog(@"[net] 第二道：dataTaskWithRequest 已接管");
        }
        if (SB_hookInstance(sess, @selector(dataTaskWithURL:completionHandler:),
                            (IMP)SB_taskURLCB)) {
            SBLog(@"[net] 第二道：dataTaskWithURL 已接管");
        }
    }
}
