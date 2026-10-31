// 02-capture.m — 网络明文捕获
//
// 纯观测：包装 completionHandler 记录数据后原样透传，不改任何行为。
// 逆向已确认目标只用这两个选择器：
//   dataTaskWithRequest:completionHandler:
//   dataTaskWithURL:completionHandler:
// delegate 路径另挂 dataTaskWithRequest: 记录请求发起。
//
// ARC 下 block 捕获对象自动持有，无野指针风险。

#import "01-shared.h"
#include <stdlib.h>

static void rc_logRequest(NSString *tag, NSURLRequest *req) {
    if (!req) return;

    RC(@"[%@] → %@ %@",
       tag,
       [req HTTPMethod] ? [req HTTPMethod] : @"?",
       [[req URL] absoluteString] ? [[req URL] absoluteString] : @"(nil)");

    NSDictionary *headers = [req allHTTPHeaderFields];
    if (headers.count) {
        RC(@"[%@]   请求头: %@", tag, headers);
    }

    NSData *body = [req HTTPBody];
    if (body && body.length) {
        RC(@"[%@]   请求体(%lu字节):\n%@", tag,
           (unsigned long)body.length, RCDataToText(body));
    }
}

static void rc_logResponse(NSString *tag, NSData *data,
                           NSURLResponse *resp, NSError *error) {
    if (error) {
        RC(@"[%@] ← 错误: %@ (code=%ld)", tag,
           [error localizedDescription], (long)[error code]);
        return;
    }

    if ([resp isKindOfClass:[NSHTTPURLResponse class]]) {
        NSHTTPURLResponse *h = (NSHTTPURLResponse *)resp;
        RC(@"[%@] ← HTTP %ld", tag, (long)[h statusCode]);
        NSDictionary *hd = [h allHeaderFields];
        if (hd.count) RC(@"[%@]   响应头: %@", tag, hd);
    } else if (resp) {
        RC(@"[%@] ← 响应类型 %@", tag, NSStringFromClass([resp class]));
    }

    if (data && data.length) {
        RC(@"[%@]   响应体(%lu字节):\n%@", tag,
           (unsigned long)data.length, RCDataToText(data));
    } else {
        RC(@"[%@]   响应体: (空)", tag);
    }
}

#pragma mark - dataTaskWithRequest:completionHandler:

typedef id (*PFN_REQ_CB)(id, SEL, NSURLRequest *,
                         void (^)(NSData *, NSURLResponse *, NSError *));

static id RC_taskRequestCB(id self, SEL _cmd, NSURLRequest *req,
                           void (^handler)(NSData *, NSURLResponse *, NSError *)) {
    static PFN_REQ_CB orig = NULL;
    static int done = 0;
    if (!done) {
        orig = (PFN_REQ_CB)RCOrigIMP(@"NSURLSession",
                                     @"dataTaskWithRequest:completionHandler:");
        done = 1;
    }
    if (!orig) {
        // 原实现缺失时安全降级：不包装，直接交给系统
        RC(@"!! dataTaskWithRequest 原实现缺失");
        return nil;
    }

    if (!handler) return orig(self, _cmd, req, handler);

    rc_logRequest(@"REQ", req);

    // ARC：捕获 req/handler 自动持有
    void (^wrap)(NSData *, NSURLResponse *, NSError *) =
    ^(NSData *data, NSURLResponse *resp, NSError *error) {
        RC_SAFE_BEGIN
            rc_logResponse(@"REQ", data, resp, error);
        RC_SAFE_END
        handler(data, resp, error);
    };

    id task = orig(self, _cmd, req, wrap);
    RC(@"[REQ] task=%@", task ? NSStringFromClass([task class]) : @"(nil)");
    return task;
}

#pragma mark - dataTaskWithURL:completionHandler:

typedef id (*PFN_URL_CB)(id, SEL, NSURL *,
                         void (^)(NSData *, NSURLResponse *, NSError *));

static id RC_taskURLCB(id self, SEL _cmd, NSURL *url,
                       void (^handler)(NSData *, NSURLResponse *, NSError *)) {
    static PFN_URL_CB orig = NULL;
    static int done = 0;
    if (!done) {
        orig = (PFN_URL_CB)RCOrigIMP(@"NSURLSession",
                                     @"dataTaskWithURL:completionHandler:");
        done = 1;
    }
    if (!orig) {
        RC(@"!! dataTaskWithURL 原实现缺失");
        return nil;
    }

    if (!handler) return orig(self, _cmd, url, handler);

    NSURLRequest *req = [NSURLRequest requestWithURL:url];
    rc_logRequest(@"URL", req);

    void (^wrap)(NSData *, NSURLResponse *, NSError *) =
    ^(NSData *data, NSURLResponse *resp, NSError *error) {
        RC_SAFE_BEGIN
            rc_logResponse(@"URL", data, resp, error);
        RC_SAFE_END
        handler(data, resp, error);
    };

    return orig(self, _cmd, url, wrap);
}

#pragma mark - delegate 路径：只记录不干预

typedef id (*PFN_REQ)(id, SEL, NSURLRequest *);

static id RC_taskRequest(id self, SEL _cmd, NSURLRequest *req) {
    static PFN_REQ orig = NULL;
    static int done = 0;
    if (!done) {
        orig = (PFN_REQ)RCOrigIMP(@"NSURLSession", @"dataTaskWithRequest:");
        done = 1;
    }
    rc_logRequest(@"DELEGATE", req);
    return orig ? orig(self, _cmd, req) : nil;
}

#pragma mark - 安装

void RCInstallCapture(void) {
    RCSection(@"网络捕获");

    Class sess = NSClassFromString(@"NSURLSession");
    if (!sess) {
        RC(@"NSURLSession 不存在");
        return;
    }

    RCHookInstance(sess, @selector(dataTaskWithRequest:completionHandler:),
                   (IMP)RC_taskRequestCB);
    RCHookInstance(sess, @selector(dataTaskWithURL:completionHandler:),
                   (IMP)RC_taskURLCB);
    RCHookInstance(sess, @selector(dataTaskWithRequest:), (IMP)RC_taskRequest);
}
