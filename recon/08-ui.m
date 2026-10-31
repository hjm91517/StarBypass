// 08-ui.m — 应用内 UI：悬浮球 + 日志面板
//
// 交互契约：
//   点球      → 展开日志面板
//   点球再次  → 收起面板
//   拖球      → 跟手移动，松手弹簧吸附最近边缘
//
// 可靠性设计（这是本文件的核心，不是附加项）：
//   1. 单个 pan 手势同时处理点击与拖动 —— 避免 tap/pan 手势冲突导致点了没反应
//   2. 窗口创建五重兜底，任何一条成功即显示
//   3. 尺寸取自 window/scene，不用 UIScreen.bounds（横屏下是固定竖屏值，会错位）
//   4. 每 2 秒自愈：球脱离视图树或 window 被隐藏时自动重建
//   5. 层级固定 10000，高于 alert（2000）与 app 自己的浮窗
//   6. 不抢 key window，不破坏 app 输入

#import "01-shared.h"
#import <UIKit/UIKit.h>

#define RC_WINDOW_LEVEL   10000.0
#define RC_BALL_SIZE      56.0
#define RC_UI_VERSION     "v3"

void RCInstallUIWindow(void);

#pragma mark - 穿透视图

// 自身不接收触摸，子视图照常。返回 nil 让触摸落到下层 app
@interface SBPassthroughView : UIView
@end

@implementation SBPassthroughView
- (UIView *)hitTest:(CGPoint)point withEvent:(id)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return (hit == self) ? nil : hit;
}
@end

@interface SBWindow : UIWindow
@end

@implementation SBWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(id)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return (hit == self) ? nil : hit;
}
@end

#pragma mark - 状态

static SBWindow *g_window = nil;
static UIView   *g_host = nil;
static UIView   *g_ball = nil;
static UIView   *g_panel = nil;
static UITextView *g_text = nil;
static NSTimer  *g_refresh = nil;
static NSTimer  *g_heal = nil;
static BOOL      g_panelOpen = NO;
static UIWindow *g_lastWindow = nil;
static int       g_attempts = 0;
static id        g_actions = nil;

#pragma mark - 窗口探测

static UIWindow *rc_keyWindow(void) {
    UIApplication *app = [UIApplication sharedApplication];
    if (!app) return nil;

    UIWindow *kw = [app keyWindow];
    if (kw) return kw;

    if (g_lastWindow) return g_lastWindow;

    NSArray *allWins = [app windows];
    if (allWins) {
        for (id w in allWins) {
            if (![w isKindOfClass:[UIWindow class]]) continue;
            if ([(UIWindow *)w isKeyWindow]) return (UIWindow *)w;
        }
        for (id w in allWins) {
            if ([w isKindOfClass:[UIWindow class]]) return (UIWindow *)w;
        }
    }

    NSArray *scenes = [app connectedScenes];
    if (!scenes) return nil;
    for (id sc in scenes) {
        if (![sc isKindOfClass:[UIWindowScene class]]) continue;
        NSArray *wins = [(UIWindowScene *)sc windows];
        if (!wins) continue;
        for (id w in wins) {
            if (![w isKindOfClass:[UIWindow class]]) continue;
            if ([(UIWindow *)w isKeyWindow]) return (UIWindow *)w;
        }
        for (id w in wins) {
            if ([w isKindOfClass:[UIWindow class]]) return (UIWindow *)w;
        }
    }
    return nil;
}

// 取一个可用的 UIWindowScene，多种来源依次尝试
static UIWindowScene *rc_findScene(void) {
    UIApplication *app = [UIApplication sharedApplication];
    if (!app) return nil;

    if (g_lastWindow) {
        UIWindowScene *s = [g_lastWindow windowScene];
        if (s) return s;
    }

    UIWindow *kw = rc_keyWindow();
    if (kw) {
        UIWindowScene *s = [kw windowScene];
        if (s) return s;
    }

    NSArray *scenes = [app connectedScenes];
    if (scenes) {
        for (id sc in scenes) {
            if ([sc isKindOfClass:[UIWindowScene class]]) return (UIWindowScene *)sc;
        }
    }
    return nil;
}

// 尺寸：优先 window bounds，其次 scene coordinateSpace，最后 UIScreen
static CGRect rc_hostBounds(UIWindow *w, UIWindowScene *sc) {
    if (w) {
        CGRect b = [w bounds];
        if (b.size.width > 1 && b.size.height > 1) return b;
    }
    if (sc) {
        UICoordinateSpace *cs = [sc coordinateSpace];
        if (cs) {
            CGRect b = [cs bounds];
            if (b.size.width > 1 && b.size.height > 1) return b;
        }
    }
    return [UIScreen mainScreen].bounds;
}

#pragma mark - 按钮工厂

static UIView *rc_button(NSString *title, SEL action, id target,
                         UIColor *bg, CGRect frame) {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setFrame:frame];
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [b setBackgroundColor:bg];
    [[b layer] setCornerRadius:8];
    [[b layer] setMasksToBounds:YES];
    [b addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

static UIView *rc_label(NSString *text, CGFloat x, CGFloat y, CGFloat w, CGFloat h,
                        UIFont *font, UIColor *color) {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(x, y, w, h)];
    [l setText:text];
    [l setFont:font];
    [l setTextColor:color];
    return l;
}

#pragma mark - 面板动作

@interface RCActions : NSObject
- (void)refresh;
- (void)doCopy;
- (void)doShare;
- (void)doClear;
- (void)doClose;
@end

@implementation RCActions

- (void)refresh {
    if (!g_text || !g_panelOpen) return;
    NSString *snap = RCMemLogSnapshot();
    if (!snap) return;
    if ([snap isEqualToString:[g_text text]]) return;
    [g_text setText:snap];

    CGSize cs = [g_text contentSize];
    CGRect b = [g_text bounds];
    if (cs.height > b.size.height) {
        [g_text setContentOffset:CGPointMake(0, cs.height - b.size.height)];
    }
}

- (void)doCopy {
    NSString *snap = RCMemLogSnapshot();
    UIPasteboard *pb = [UIPasteboard generalPasteboard];
    if (pb && snap) {
        [pb setString:snap];
        RC(@"[UI] 已复制 %lu 字符到剪贴板", (unsigned long)snap.length);
    }
}

- (void)doShare {
    NSString *snap = RCMemLogSnapshot();
    if (!snap || snap.length == 0) return;

    NSString *path = [NSTemporaryDirectory()
                      stringByAppendingPathComponent:
                      [NSString stringWithUTF8String:RC_CFG_LOG_NAME]];
    [snap writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];

    UIWindow *kw = rc_keyWindow();
    UIViewController *vc = kw ? [kw rootViewController] : nil;
    if (!vc && g_window) vc = [g_window rootViewController];
    if (!vc) return;

    NSURL *url = [NSURL fileURLWithPath:path];
    NSArray *items = url ? @[url] : @[snap];
    // 顶层 VC：避免在已 present 的 VC 上再次 present 失败
    UIViewController *top = vc;
    while ([top presentedViewController]) {
        top = [top presentedViewController];
    }

    UIActivityViewController *av =
        [[UIActivityViewController alloc] initWithActivityItems:items
                                          applicationActivities:nil];

    // iPad 必需：不设 popover 锚点会直接抛异常崩溃
    UIPopoverPresentationController *pop = [av popoverPresentationController];
    if (pop) {
        CGRect anchor = CGRectMake(0, 0, 1, 1);
        if (g_panel) {
            CGRect pb = [g_panel bounds];
            anchor = CGRectMake(pb.size.width / 2, pb.size.height / 2, 1, 1);
        }
        [pop setSourceView:g_panel ? g_panel : [top view]];
        [pop setSourceRect:anchor];
    }

    [top presentViewController:av animated:YES completion:nil];
}

- (void)doClear {
    RCMemLogClear();
    if (g_text) [g_text setText:@""];
    RC(@"[UI] 日志已清空");
}

- (void)doClose {
    [RCActions closePanel];
}

// 自愈节拍：球脱离视图树或 window 被隐藏时恢复
- (void)healTick {
    if (!g_ball) return;
    UIView *sp = [g_ball superview];
    if (!sp) {
        RC(@"[UI] 自愈：球脱离视图树，重新挂载");
        if (g_host) [g_host addSubview:g_ball];
        return;
    }
    if (g_window && [g_window isHidden]) {
        RC(@"[UI] 自愈：window 被隐藏，重新显示");
        [g_window setHidden:NO];
    }
}

+ (void)closePanel {
    if (!g_panel || !g_panelOpen) return;
    g_panelOpen = NO;
    [UIView animateWithDuration:0.16
                          delay:0
                        options:UIViewAnimationOptionCurveEaseInOut
                     animations:^{
        [g_panel setAlpha:0];
    } completion:^(BOOL done) {
        [g_panel setHidden:YES];
    }];
}

+ (void)openPanel {
    if (!g_panel || g_panelOpen) return;

    CGRect pb = [g_panel bounds];
    CGRect hb = g_host ? [g_host bounds] : [UIScreen mainScreen].bounds;

    // 从球所在的一侧展开，避免被球挡住
    CGPoint bc = g_ball ? [g_ball center] : CGPointMake(hb.size.width - 40, 200);
    CGFloat cx = (bc.x > hb.size.width / 2)
                 ? (hb.size.width - pb.size.width / 2 - 16)
                 : (pb.size.width / 2 + 16);
    CGFloat cy = hb.size.height / 2;
    if (cy + pb.size.height / 2 > hb.size.height - 30)
        cy = hb.size.height - pb.size.height / 2 - 30;
    if (cy - pb.size.height / 2 < 40)
        cy = pb.size.height / 2 + 40;

    [g_panel setCenter:CGPointMake(cx, cy)];
    [g_panel setAlpha:0];
    [g_panel setHidden:NO];
    g_panelOpen = YES;

    [UIView animateWithDuration:0.42
                          delay:0
         usingSpringWithDamping:0.80
          initialSpringVelocity:0.5
                        options:UIViewAnimationOptionCurveEaseInOut
                     animations:^{
        [g_panel setAlpha:1];
    } completion:nil];

    if (g_text) [g_text setText:RCMemLogSnapshot()];

    // 球必须在面板之上，否则面板会挡住球，点不到就收不起来
    if (g_host && g_ball) [g_host bringSubviewToFront:g_ball];
}

@end

#pragma mark - 悬浮球：单手势同时处理点击与拖动

@interface RCBallCtrl : NSObject
- (void)onTap:(id)g;
- (void)onPan:(UIPanGestureRecognizer *)g;
@end

@implementation RCBallCtrl

// 轻点：切换面板
- (void)onTap:(id)g {
    if (g_panelOpen) [RCActions closePanel];
    else [RCActions openPanel];
}

- (void)onPan:(UIPanGestureRecognizer *)g {
    if (!g_ball) return;

    CGPoint t = [g translationInView:g_host];
    [g setTranslation:CGPointZero inView:g_host];

    CGPoint c = [g_ball center];
    CGPoint nc = CGPointMake(c.x + t.x, c.y + t.y);

    CGRect hb = g_host ? [g_host bounds] : [UIScreen mainScreen].bounds;
    CGFloat half = RC_BALL_SIZE / 2;

    if (nc.x < half + 4) nc.x = half + 4;
    if (nc.x > hb.size.width - half - 4) nc.x = hb.size.width - half - 4;
    if (nc.y < half + 30) nc.y = half + 30;
    if (nc.y > hb.size.height - half - 20) nc.y = hb.size.height - half - 20;

    // 跟手：直接设 center，不做插值
    [g_ball setCenter:nc];

    long state = (long)[g state];

    if (state == UIGestureRecognizerStateEnded ||
        state == UIGestureRecognizerStateCancelled) {
        // 拖动结束：吸附最近边缘
        CGFloat targetX = (nc.x < hb.size.width / 2)
                          ? (half + 12) : (hb.size.width - half - 12);
        [UIView animateWithDuration:0.48
                              delay:0
             usingSpringWithDamping:0.72
              initialSpringVelocity:0.7
                            options:UIViewAnimationOptionCurveEaseInOut |
                                    UIViewAnimationOptionBeginFromCurrentState
                         animations:^{
            [g_ball setCenter:CGPointMake(targetX, nc.y)];
        } completion:nil];
    }
}

@end

static RCBallCtrl *g_ctrl = nil;

#pragma mark - 构建

static BOOL rc_buildUI(void) {
    // ── 1. 选宿主 ──
    UIWindowScene *scene = rc_findScene();
    UIWindow *appWin = rc_keyWindow();

    RC(@"[UI] 探测 scene=%@ appWin=%@",
       scene ? @"有" : @"无", appWin ? @"有" : @"无");

    UIWindow *prevKey = appWin;
    CGRect hb = CGRectMake(0, 0, 0, 0);

    // 方案 A：自建高层 window（能压过 alert 与 app 浮窗）
    if (scene) {
        g_window = [[SBWindow alloc] initWithWindowScene:scene];
        if (g_window) {
            hb = rc_hostBounds(g_window, scene);
            if (hb.size.width < 1) hb = rc_hostBounds(appWin, scene);
            [g_window setFrame:hb];
            [g_window setWindowLevel:RC_WINDOW_LEVEL];
            [g_window setBackgroundColor:[UIColor clearColor]];

            UIViewController *vc = [[UIViewController alloc] init];
            SBPassthroughView *v =
                [[SBPassthroughView alloc] initWithFrame:
                    CGRectMake(0, 0, hb.size.width, hb.size.height)];
            [v setBackgroundColor:[UIColor clearColor]];
            [vc setView:v];
            [g_window setRootViewController:vc];
            g_host = v;

            [g_window makeKeyAndVisible];
            [g_window setHidden:NO];
            if (prevKey && prevKey != g_window && [prevKey canBecomeKeyWindow]) {
                [prevKey makeKeyWindow];
            }
            RC(@"[UI] 方案A 自建 window 成功 level=%.0f size=%.0fx%.0f",
               (double)RC_WINDOW_LEVEL,
               (double)hb.size.width, (double)hb.size.height);
        }
    }

    // 方案 B：挂到 app 的 keyWindow（保底可见）
    if (!g_host) {
        UIWindow *kw = appWin;
        if (kw) {
            UIViewController *rvc = [kw rootViewController];
            UIView *base = rvc ? [rvc view] : kw;
            if (base) {
                hb = [base bounds];
                if (hb.size.width < 1) hb = [kw bounds];
                SBPassthroughView *v =
                    [[SBPassthroughView alloc] initWithFrame:
                        CGRectMake(0, 0, hb.size.width, hb.size.height)];
                [v setBackgroundColor:[UIColor clearColor]];
                [base addSubview:v];
                [base bringSubviewToFront:v];
                g_host = v;
                RC(@"[UI] 方案B 挂到 keyWindow 成功 size=%.0fx%.0f",
                   (double)hb.size.width, (double)hb.size.height);
            }
        }
    }

    if (!g_host) {
        RC(@"!! 无可用宿主窗口");
        return NO;
    }

    if (hb.size.width < 100 || hb.size.height < 100) {
        hb = [UIScreen mainScreen].bounds;
    }
    if (hb.size.width < 100 || hb.size.height < 100) {
        RC(@"!! 宿主尺寸异常 %.0fx%.0f",
           (double)hb.size.width, (double)hb.size.height);
        return NO;
    }

    // ── 2. 悬浮球 ──
    if (!g_ctrl) g_ctrl = [[RCBallCtrl alloc] init];

    CGFloat half = RC_BALL_SIZE / 2;
    CGFloat bx = hb.size.width - RC_BALL_SIZE - 12;
    CGFloat by = hb.size.height * 0.28;
    if (bx < 4) bx = 4;
    if (by < RC_BALL_SIZE + 24) by = RC_BALL_SIZE + 24;
    if (by > hb.size.height - RC_BALL_SIZE - 20)
        by = hb.size.height - RC_BALL_SIZE - 20;
    if (by < 4) by = 4;

    g_ball = [[UIView alloc] initWithFrame:
              CGRectMake(bx, by, RC_BALL_SIZE, RC_BALL_SIZE)];
    [g_ball setBackgroundColor:
        [UIColor colorWithRed:0.10 green:0.11 blue:0.14 alpha:0.94]];
    [[g_ball layer] setCornerRadius:half];
    [[g_ball layer] setMasksToBounds:NO];
    [[g_ball layer] setBorderWidth:2.0];
    [[g_ball layer] setBorderColor:
        [[UIColor colorWithRed:0.32 green:0.78 blue:0.98 alpha:1] CGColor]];
    [[g_ball layer] setShadowColor:[[UIColor blackColor] CGColor]];
    [[g_ball layer] setShadowOpacity:0.4];
    [[g_ball layer] setShadowRadius:6];
    [[g_ball layer] setShadowOffset:CGSizeMake(0, 2)];

    UILabel *glyph = [[UILabel alloc] initWithFrame:
                      CGRectMake(0, 0, RC_BALL_SIZE, RC_BALL_SIZE)];
    [glyph setText:[NSString stringWithFormat:@"R%s", RC_CFG_UI_TAG]];
    [glyph setTextAlignment:NSTextAlignmentCenter];
    [glyph setFont:[UIFont boldSystemFontOfSize:13]];
    [glyph setTextColor:[UIColor colorWithRed:0.32 green:0.78 blue:0.98 alpha:1]];
    [g_ball addSubview:glyph];

    // 只用一个 pan 手势：轻点=切换面板，拖动=移动球
    UITapGestureRecognizer *tap =
        [[UITapGestureRecognizer alloc] initWithTarget:g_ctrl
                                                action:@selector(onTap:)];
    [tap setCancelsTouchesInView:NO];
    [g_ball addGestureRecognizer:tap];

    UIPanGestureRecognizer *pan =
        [[UIPanGestureRecognizer alloc] initWithTarget:g_ctrl
                                                action:@selector(onPan:)];
    [pan setCancelsTouchesInView:NO];
    [g_ball addGestureRecognizer:pan];

    // 拖动时不要误触发点击
    [tap requireGestureRecognizerToFail:pan];
    RC(@"[UI] 手势就位：tap=切换面板 pan=拖动");

    [g_host addSubview:g_ball];

    // ── 3. 日志面板 ──
    CGFloat pw = hb.size.width - 40;
    if (pw > 560) pw = 560;
    if (pw < 240) pw = 240;
    CGFloat ph = hb.size.height * 0.66;
    if (ph > 520) ph = 520;
    if (ph < 260) ph = 260;

    UIView *panel = [[UIView alloc] initWithFrame:CGRectMake(0, 0, pw, ph)];
    [panel setCenter:CGPointMake(hb.size.width / 2, hb.size.height / 2)];
    [panel setBackgroundColor:
        [UIColor colorWithRed:0.07 green:0.08 blue:0.11 alpha:0.98]];
    [[panel layer] setCornerRadius:16];
    [[panel layer] setMasksToBounds:YES];
    [panel setHidden:YES];
    [panel setAlpha:0];

    RCActions *act = [[RCActions alloc] init];

    // 标题栏
    [panel addSubview:rc_label(@"StarRecon 日志",
                               16, 8, pw - 120, 22,
                               [UIFont boldSystemFontOfSize:16],
                               [UIColor whiteColor])];
    [panel addSubview:rc_label(@"点悬浮球可收起",
                               pw - 130, 10, 114, 18,
                               [UIFont systemFontOfSize:11],
                               [UIColor lightGrayColor])];

    // 按钮行
    CGFloat gap = 6;
    CGFloat bw = (pw - 24 - gap * 3) / 4.0;
    CGFloat by2 = 36;
    [panel addSubview:rc_button(@"复制", @selector(doCopy), act,
        [UIColor colorWithRed:0.16 green:0.40 blue:0.68 alpha:1],
        CGRectMake(12, by2, bw, 28))];
    [panel addSubview:rc_button(@"分享", @selector(doShare), act,
        [UIColor colorWithRed:0.14 green:0.48 blue:0.32 alpha:1],
        CGRectMake(12 + (bw + gap), by2, bw, 28))];
    [panel addSubview:rc_button(@"清空", @selector(doClear), act,
        [UIColor colorWithRed:0.44 green:0.31 blue:0.10 alpha:1],
        CGRectMake(12 + (bw + gap) * 2, by2, bw, 28))];
    [panel addSubview:rc_button(@"关闭", @selector(doClose), act,
        [UIColor colorWithRed:0.50 green:0.17 blue:0.18 alpha:1],
        CGRectMake(12 + (bw + gap) * 3, by2, bw, 28))];

    // 日志文本
    g_text = [[UITextView alloc] initWithFrame:
              CGRectMake(12, 72, pw - 24, ph - 84)];
    [g_text setEditable:NO];
    [g_text setSelectable:YES];
    [g_text setBackgroundColor:
        [UIColor colorWithRed:0.03 green:0.04 blue:0.06 alpha:1]];
    [g_text setTextColor:
        [UIColor colorWithRed:0.70 green:0.84 blue:0.70 alpha:1]];
    [g_text setFont:[UIFont monospacedSystemFontOfSize:10 weight:0]];
    [[g_text layer] setCornerRadius:8];
    [[g_text layer] setMasksToBounds:YES];
    [panel addSubview:g_text];

    [g_host addSubview:panel];
    g_panel = panel;

    // 球永远在面板之上
    [g_host bringSubviewToFront:g_ball];

    RC(@"[UI] 悬浮球就位 宿主=%.0fx%.0f 球=(%.0f,%.0f) 版本=%s",
       (double)hb.size.width, (double)hb.size.height,
       (double)bx + half, (double)by + half, RC_UI_VERSION);
    return YES;
}

#pragma mark - 自愈

#pragma mark - 安装

void RCInstallUIWindow(void) {
    if (g_ball) return;

    if (g_attempts >= 60) {
        RC(@"!! UI 创建 60 次仍失败");
        return;
    }
    g_attempts++;

    RCSection(@"应用内 UI");
    RC(@"[UI] 第 %d 次尝试 版本=%s", g_attempts, RC_UI_VERSION);

    BOOL ok = NO;
    RC_SAFE_BEGIN
        ok = rc_buildUI();
    RC_SAFE_END

    if (!ok) {
        // 清掉半成品，否则下次进来会被"已存在"判断挡住
        if (g_ball) { [g_ball removeFromSuperview]; g_ball = nil; }
        if (g_panel) { [g_panel removeFromSuperview]; g_panel = nil; }
        if (g_host) { [g_host removeFromSuperview]; g_host = nil; }
        if (g_window) { [g_window setHidden:YES]; g_window = nil; }
        g_text = nil;
        g_panelOpen = NO;

        RC(@"[UI] 失败，1.5s 后重试");
        RCAfterSec(1.5, ^{
            RCInstallUIWindow();
        });
        return;
    }

    if (!g_actions) g_actions = [[RCActions alloc] init];

    // 刷新定时器
    if (g_refresh) [g_refresh invalidate];
    g_refresh = [NSTimer scheduledTimerWithTimeInterval:0.6
                                                 target:g_actions
                                               selector:@selector(refresh)
                                               userInfo:nil
                                                repeats:YES];

    // 自愈定时器
    if (!g_heal) {
        g_heal = [NSTimer scheduledTimerWithTimeInterval:2.0
                                                  target:g_actions
                                                selector:@selector(healTick)
                                                userInfo:nil
                                                 repeats:YES];
    }

    RC(@"[UI] 完成：点球开日志，再点收起，拖动换位置");
}

#pragma mark - present 时机补建

void RCInstallUIPresentHook(void) {
    static int done = 0;
    if (done) return;
    done = 1;

    Class vcCls = NSClassFromString(@"UIViewController");
    if (!vcCls) return;

    SEL sel = @selector(presentViewController:animated:completion:);
    Method m = class_getInstanceMethod(vcCls, sel);
    if (!m) return;

    IMP orig = method_getImplementation(m);
    RCStoreIMP(@"UIViewController",
               @"presentViewController:animated:completion:", orig);

    IMP nb = imp_implementationWithBlock(
        ^(id self, UIViewController *vc, BOOL animated, void (^comp)(void)) {
        ((void (*)(id, SEL, UIViewController *, BOOL, void (^)(void)))orig)
            (self, sel, vc, animated, comp);

        RC_SAFE_BEGIN
            UIView *v = [self view];
            UIWindow *w = v ? [v window] : nil;
            if (w) {
                g_lastWindow = w;
                if (!g_ball) {
                    RC(@"[UI] present 抓到 window，补建 UI");
                    RCAfterSec(0.4, ^{ RCInstallUIWindow(); });
                }
            }
        RC_SAFE_END
    });
    class_replaceMethod(vcCls, sel, nb, method_getTypeEncoding(m));
    RC(@"[UI] present hook 就位");
}
