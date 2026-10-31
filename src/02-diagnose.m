// 02-diagnose.m — 运行时诊断层
//
// 作用有两层：
//   1. 抓真相：界面上任何失败提示出现时，打印文案 + 调用栈 + 涉及的类，
//      这样就能确定到底是哪个方法在拦。
//   2. 兜底改写：配置允许时，把失败文案直接换成成功文案，
//      保证用户看到的是已授权状态。
//
// 覆盖的显示入口：UILabel / UITextView / UIButton / UIAlertController

#import "01-shared.h"
#import <UIKit/UIKit.h>
#include <string.h>
#include <stdlib.h>

#pragma mark - 文案判定

static NSArray *SB_failureKeywords(void) {
    return @[@"不存在", @"失败", @"错误", @"无效", @"过期", @"未授权",
             @"未激活", @"未绑定", @"不正确", @"不能用", @"已被使用",
             @"请输入正确", @"请先", @"余额不足", @"禁止", @"拒绝"];
}

static NSArray *SB_successKeywords(void) {
    return @[@"成功", @"已激活", @"已授权", @"已绑定", @"有效期"];
}

BOOL SB_isFailureText(NSString *text) {
    if (![text isKindOfClass:[NSString class]] || text.length == 0) return NO;

    BOOL hasFail = NO;
    for (NSString *k in SB_failureKeywords()) {
        if ([text containsString:k]) { hasFail = YES; break; }
    }
    if (!hasFail) return NO;

    for (NSString *k in SB_successKeywords()) {
        if ([text containsString:k]) return NO;
    }
    return YES;
}

// 把失败文案换成成功文案
static NSString *SB_successText(void) {
    return [NSString stringWithUTF8String:SB_CFG_SUCCESS_TEXT];
}

static void SB_reportFailure(NSString *text, const char *where) {
    SBLog(@"=== 捕获失败提示 [%s] ===", where);
    SBLog(@"文案: %@", text);

    // 调用栈：定位到具体产生该文案的方法
    if (!SB_CFG_TRACE_STACK) return;
    @try {
        NSArray *stack = [[NSThread currentThread] callStackSymbols];
        NSUInteger n = stack.count;
        if (n > SB_CFG_TRACE_DEPTH) n = SB_CFG_TRACE_DEPTH;
        for (NSUInteger i = 0; i < n; i++) {
            SBLog(@"  #%lu %@", (unsigned long)i, [stack objectAtIndex:i]);
        }
    } @catch (...) {
        SBLog(@"  (调用栈不可用)");
    }
}

#pragma mark - UILabel

static void SB_UILabel_setText(id self, SEL _cmd, NSString *text) {
    static void (*orig)(id, SEL, NSString *) = NULL;
    static int done = 0;
    if (!done) {
        orig = (void (*)(id, SEL, NSString *))SB_origIMP(@"UILabel", @"setText:");
        done = 1;
    }

    if (SB_isFailureText(text)) {
        SB_reportFailure(text, "UILabel.setText:");
        if (SB_overrideFailureText()) {
            text = SB_successText();
            SB_persistAuthorized(nil, nil);
        }
    }

    if (orig) orig(self, _cmd, text);
}

#pragma mark - UITextView

static void SB_UITextView_setText(id self, SEL _cmd, NSString *text) {
    static void (*orig)(id, SEL, NSString *) = NULL;
    static int done = 0;
    if (!done) {
        orig = (void (*)(id, SEL, NSString *))SB_origIMP(@"UITextView", @"setText:");
        done = 1;
    }
    if (SB_isFailureText(text)) {
        SB_reportFailure(text, "UITextView.setText:");
        if (SB_overrideFailureText()) {
            text = SB_successText();
            SB_persistAuthorized(nil, nil);
        }
    }
    if (orig) orig(self, _cmd, text);
}

#pragma mark - UIButton

static void SB_UIButton_setTitle(id self, SEL _cmd, NSString *title, NSUInteger state) {
    static void (*orig)(id, SEL, NSString *, NSUInteger) = NULL;
    static int done = 0;
    if (!done) {
        orig = (void (*)(id, SEL, NSString *, NSUInteger))
            SB_origIMP(@"UIButton", @"setTitle:forState:");
        done = 1;
    }
    if (SB_isFailureText(title) && SB_overrideFailureText()) {
        SB_reportFailure(title, "UIButton.setTitle:");
        title = @"已授权";
        SB_persistAuthorized(nil, nil);
    }
    if (orig) orig(self, _cmd, title, state);
}

#pragma mark - UIAlertController

static id SB_UIAlertController_create(Class cls, SEL _cmd, NSString *title,
                                      NSString *message, long style) {
    static id (*orig)(Class, SEL, NSString *, NSString *, long) = NULL;
    static int done = 0;
    if (!done) {
        orig = (id (*)(Class, SEL, NSString *, NSString *, long))
            SB_origIMP(@"+UIAlertController", @"alertControllerWithTitle:message:preferredStyle:");
        done = 1;
    }

    if (SB_isFailureText(message) || SB_isFailureText(title)) {
        SB_reportFailure(message ? message : title, "UIAlertController.create");
        if (SB_overrideFailureText()) {
            title = @"授权成功";
            message = SB_successText();
            SB_persistAuthorized(nil, nil);
        }
    }
    if (orig) return orig(cls, _cmd, title, message, style);
    return nil;
}

#pragma mark - 类结构 dump（确认目标类与已 hook 方法）

void SB_dumpClass(NSString *clsName) {
    Class cls = NSClassFromString(clsName);
    if (!cls) {
        SBLog(@"dump: 类 %@ 未加载", clsName);
        return;
    }

    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    SBLog(@"dump: %@ 共 %u 个实例方法", clsName, count);
    if (methods) {
        for (unsigned int i = 0; i < count && i < 64; i++) {
            SEL sel = method_getName(methods[i]);
            SBLog(@"  -[%@ %@]", clsName, NSStringFromSelector(sel));
        }
        free(methods);
    }

    Class meta = object_getClass(cls);
    unsigned int ccount = 0;
    Method *cms = class_copyMethodList(meta, &ccount);
    if (cms) {
        SBLog(@"dump: %@ 共 %u 个类方法", clsName, ccount);
        for (unsigned int i = 0; i < ccount && i < 32; i++) {
            SBLog(@"  +[%@ %@]", clsName,
                  NSStringFromSelector(method_getName(cms[i])));
        }
        free(cms);
    }
}

#pragma mark - 安装

void SB_installDiagnose(void) {
    Class label = NSClassFromString(@"UILabel");
    if (label) {
        SB_hookInstance(label, @selector(setText:), (IMP)SB_UILabel_setText);
    }

    Class tv = NSClassFromString(@"UITextView");
    if (tv) {
        SB_hookInstance(tv, @selector(setText:), (IMP)SB_UITextView_setText);
    }

    Class btn = NSClassFromString(@"UIButton");
    if (btn) {
        SB_hookInstance(btn, @selector(setTitle:forState:), (IMP)SB_UIButton_setTitle);
    }

    Class alert = NSClassFromString(@"UIAlertController");
    if (alert) {
        SB_hookClass(alert,
                     @selector(alertControllerWithTitle:message:preferredStyle:),
                     (IMP)SB_UIAlertController_create);
    }

    // 打印目标类结构，确认 hook 是否落在正确位置
    SB_dumpClass(@"KQ7mV2xN9R");
    SB_dumpClass(@"STARSMenuView");
}
