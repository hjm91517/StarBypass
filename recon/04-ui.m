// 04-ui.m — 界面文案追踪
//
// 目的：定位"卡密不存在"这类提示由哪个方法产生。
// 手段：hook 所有文案显示入口，命中关键词时打印完整调用栈。
// 不改写任何文案，user 看到的就是原始行为。

#import "01-shared.h"

static NSArray *rc_keywords(void) {
    return @[@"不存在", @"失败", @"错误", @"无效", @"过期", @"未授权",
             @"未激活", @"未绑定", @"不正确", @"已被使用", @"请输入",
             @"未找到", @"异常", @"拒绝", @"禁止", @"余额"];
}

static BOOL rc_isInteresting(NSString *text) {
    if (![text isKindOfClass:[NSString class]] || text.length == 0) return NO;
    for (NSString *k in rc_keywords()) {
        if ([text containsString:k]) return YES;
    }
    return NO;
}

static void rc_report(NSString *text, const char *where) {
    RC(@"★★★ 命中文案 [%s]: \"%@\"", where, text);
    if (!RC_CFG_TRACE_STACK) return;

    NSArray *stack = RCCallStack(RC_CFG_TRACE_DEPTH);
    for (NSUInteger i = 0; i < stack.count; i++) {
        RC(@"      #%lu %@", (unsigned long)i, [stack objectAtIndex:i]);
    }
    RC(@"★★★ 调用栈结束");
}

#pragma mark - UILabel

typedef void (*PFN_SETTEXT)(id, SEL, NSString *);

static void rc_labelSetText(id self, SEL _cmd, NSString *text) {
    static PFN_SETTEXT orig = NULL;
    static int done = 0;
    if (!done) {
        orig = (PFN_SETTEXT)RCOrigIMP(@"UILabel", @"setText:");
        done = 1;
    }
    if (rc_isInteresting(text)) rc_report(text, "UILabel");
    if (orig) orig(self, _cmd, text);
}

#pragma mark - UITextView

static void rc_textViewSetText(id self, SEL _cmd, NSString *text) {
    static PFN_SETTEXT orig = NULL;
    static int done = 0;
    if (!done) {
        orig = (PFN_SETTEXT)RCOrigIMP(@"UITextView", @"setText:");
        done = 1;
    }
    if (rc_isInteresting(text)) rc_report(text, "UITextView");
    if (orig) orig(self, _cmd, text);
}

#pragma mark - UIButton

typedef void (*PFN_SETTITLE)(id, SEL, NSString *, NSUInteger);

static void rc_buttonSetTitle(id self, SEL _cmd, NSString *title, NSUInteger state) {
    static PFN_SETTITLE orig = NULL;
    static int done = 0;
    if (!done) {
        orig = (PFN_SETTITLE)RCOrigIMP(@"UIButton", @"setTitle:forState:");
        done = 1;
    }
    if (rc_isInteresting(title)) rc_report(title, "UIButton");
    if (orig) orig(self, _cmd, title, state);
}

#pragma mark - UIAlertController

typedef id (*PFN_ALERT)(Class, SEL, NSString *, NSString *, long);

static id rc_alertCreate(Class cls, SEL _cmd, NSString *title,
                         NSString *message, long style) {
    static PFN_ALERT orig = NULL;
    static int done = 0;
    if (!done) {
        orig = (PFN_ALERT)RCOrigIMP(@"+UIAlertController",
                    @"alertControllerWithTitle:message:preferredStyle:");
        done = 1;
    }
    if (rc_isInteresting(title)) rc_report(title, "UIAlert.title");
    if (rc_isInteresting(message)) rc_report(message, "UIAlert.message");
    return orig ? orig(cls, _cmd, title, message, style) : nil;
}

#pragma mark - 安装

void RCInstallUI(void) {
    RCSection(@"界面文案追踪");

    Class label = NSClassFromString(@"UILabel");
    if (label) RCHookInstance(label, @selector(setText:), (IMP)rc_labelSetText);

    Class tv = NSClassFromString(@"UITextView");
    if (tv) RCHookInstance(tv, @selector(setText:), (IMP)rc_textViewSetText);

    Class btn = NSClassFromString(@"UIButton");
    if (btn) RCHookInstance(btn, @selector(setTitle:forState:),
                            (IMP)rc_buttonSetTitle);

    Class alert = NSClassFromString(@"UIAlertController");
    if (alert) RCHookClass(alert,
                           @selector(alertControllerWithTitle:message:preferredStyle:),
                           (IMP)rc_alertCreate);
}
