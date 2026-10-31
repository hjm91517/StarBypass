// 08-ui.m — 应用内 UI：悬浮球 + 日志面板
//
// 免越狱注入后拿不到 Console 也进不了沙盒，所以必须把入口做进 app。
//
// 结构：
//   SBWindow            顶层 window，空白区域触摸穿透（否则挡住 app）
//   SBPassthroughView   rootViewController 的 view，自身不接收触摸
//   SBFloatingBall      悬浮球，可拖动、松手吸附边缘
//   SBLogPanel          日志面板，显示 / 复制 / 分享 / 清空
//
// 动效：
//   拖动跟手不插值；松手用弹簧吸附到最近边缘；
//   面板以缩放+淡入从球位置展开，收起到球位置。

#import "01-shared.h"
#import <UIKit/UIKit.h>

// 远高于 alert 层，保证覆盖在最上面
#define RC_WINDOW_LEVEL 30000000.0

#pragma mark - 穿透视图

@interface SBPassthroughView : UIView
@end

@implementation SBPassthroughView
// 自身不接收触摸，子视图照常；返回 nil 让触摸落到下层 app
- (UIView *)hitTest:(CGPoint)point withEvent:(id)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return (hit == self) ? nil : hit;
}
@end

#pragma mark - 顶层窗口

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
static UIView *g_ball = nil;
static UIView *g_panel = nil;
static UITextView *g_text = nil;
static NSTimer *g_refresh = nil;
static CGPoint g_ballRest = {0, 0};
static BOOL g_panelOpen = NO;

#pragma mark - 工具

static CGRect rc_screenBounds(void) {
    UIScreen *s = [UIScreen mainScreen];
    return s ? [s bounds] : CGRectMake(0, 0, 375, 812);
}

static UIWindowScene *rc_activeScene(void) {
    UIApplication *app = [UIApplication sharedApplication];
    if (!app) return nil;
    NSArray *scenes = [app connectedScenes];
    if (!scenes || scenes.count == 0) return nil;
    for (id s in scenes) {
        if ([s isKindOfClass:[UIWindowScene class]]) return (UIWindowScene *)s;
    }
    return nil;
}

static UIView *rc_makeButton(NSString *title, SEL action, id target,
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

// 取 key window：iOS 13+ 的 UIApplication.keyWindow 在 scene 架构下可能返回 nil，
// 必须回落到 scene 的 windows 里找 isKeyWindow
static UIWindow *rc_keyWindow(void) {
    UIApplication *app = [UIApplication sharedApplication];
    if (!app) return nil;

    UIWindow *kw = [app keyWindow];
    if (kw) return kw;

    NSArray *scenes = [app connectedScenes];
    if (scenes) {
        for (id sc in scenes) {
            if (![sc isKindOfClass:[UIWindowScene class]]) continue;
            NSArray *wins = [(UIWindowScene *)sc windows];
            if (!wins) continue;
            for (id w in wins) {
                if (![w isKindOfClass:[UIWindow class]]) continue;
                UIWindow *win = (UIWindow *)w;
                if ([win isKeyWindow]) return win;
            }
            // 没有 key 就退回第一个
            for (id w in wins) {
                if ([w isKindOfClass:[UIWindow class]]) return (UIWindow *)w;
            }
        }
    }
    return nil;
}

#pragma mark - 顶层 VC

// 从 app 的 key window 找最上层 VC，用于弹出分享面板
static UIViewController *rc_topViewController(void) {
    UIWindow *kw = rc_keyWindow();
    UIViewController *vc = kw ? [kw rootViewController] : nil;
    if (!vc) vc = [g_window rootViewController];
    return vc;
}

#pragma mark - 面板

@interface SBUIActions : NSObject
- (void)doRefresh;
- (void)doCopy;
- (void)doShare;
- (void)doClear;
- (void)doClose;
@end

@implementation SBUIActions

- (void)doRefresh {
    if (!g_text) return;
    NSString *snap = RCMemLogSnapshot();
    if (!snap) return;
    if ([snap isEqualToString:[g_text text]]) return;
    [g_text setText:snap];
    // 滚到底部，日志是追加式，最新一行在末尾
    CGSize cs = [g_text contentSize];
    CGFloat h = cs.height;
    CGRect b = [g_text bounds];
    if (h > b.size.height) {
        [g_text setContentOffset:CGPointMake(0, h - b.size.height)];
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

    // 同时写一份到 Documents，方便文件 App 取
    NSString *path = [NSTemporaryDirectory()
                      stringByAppendingPathComponent:
                      [NSString stringWithUTF8String:RC_CFG_LOG_NAME]];
    [snap writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];

    UIViewController *vc = rc_topViewController();
    if (!vc) return;

    NSURL *url = [NSURL fileURLWithPath:path];
    NSArray *items = url ? @[url] : @[snap];
    UIActivityViewController *av =
        [[UIActivityViewController alloc] initWithActivityItems:items
                                          applicationActivities:nil];
    [vc presentViewController:av animated:YES completion:nil];
}

- (void)doClear {
    RCMemLogClear();
    if (g_text) [g_text setText:@""];
    RC(@"[UI] 日志已清空");
}

- (void)doClose {
    [SBUIActions closePanel];
}

+ (void)closePanel {
    if (!g_panel) return;
    g_panelOpen = NO;

    CGRect target = g_panel.bounds;
    // 收回到球位置：缩到 0.01 并淡出
    [UIView animateWithDuration:0.18
                          delay:0
         usingSpringWithDamping:1.0
          initialSpringVelocity:0
                        options:UIViewAnimationOptionCurveEaseInOut
                     animations:^{
        [g_panel setAlpha:0];
    } completion:^(BOOL done) {
        [g_panel setHidden:YES];
        [g_panel setBounds:target];
    }];
}

@end

#pragma mark - 悬浮球交互

@interface SBBallCtrl : NSObject
- (void)onTap:(id)g;
- (void)onPan:(UIPanGestureRecognizer *)g;
@end

@implementation SBBallCtrl

- (void)onTap:(id)g {
    if (g_panelOpen) {
        [SBUIActions closePanel];
        return;
    }
    if (!g_panel) return;

    CGRect sb = rc_screenBounds();
    CGFloat pw = g_panel.bounds.size.width;
    CGFloat ph = g_panel.bounds.size.height;

    // 从球位置向屏幕内侧展开
    CGPoint c = [g_ball center];
    CGFloat cx = (c.x > sb.size.width / 2) ? (sb.size.width - pw / 2 - 16)
                                           : (pw / 2 + 16);
    CGFloat cy = sb.size.height / 2;
    if (cy + ph / 2 > sb.size.height - 40) cy = sb.size.height - ph / 2 - 40;
    if (cy - ph / 2 < 60) cy = ph / 2 + 60;

    [g_panel setCenter:CGPointMake(cx, cy)];
    [g_panel setAlpha:0];
    [g_panel setHidden:NO];
    g_panelOpen = YES;

    [UIView animateWithDuration:0.45
                          delay:0
         usingSpringWithDamping:0.78
          initialSpringVelocity:0.6
                        options:UIViewAnimationOptionCurveEaseInOut
                     animations:^{
        [g_panel setAlpha:1];
    } completion:nil];
}

- (void)onPan:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:g_window];
    CGPoint c = [g_ball center];
    CGPoint nc = CGPointMake(c.x + t.x, c.y + t.y);

    CGRect sb = rc_screenBounds();
    CGFloat half = 28;
    if (nc.x < half) nc.x = half;
    if (nc.x > sb.size.width - half) nc.x = sb.size.width - half;
    if (nc.y < half + 40) nc.y = half + 40;
    if (nc.y > sb.size.height - half - 20) nc.y = sb.size.height - half - 20;

    // 跟手：直接设 center，不做插值
    [g_ball setCenter:nc];
    [g setTranslation:CGPointZero inView:g_window];

    if ([g state] == UIGestureRecognizerStateEnded ||
        [g state] == UIGestureRecognizerStateCancelled) {
        // 吸附最近边缘
        CGFloat targetX = (nc.x < sb.size.width / 2) ? (half + 8)
                                                     : (sb.size.width - half - 8);
        [UIView animateWithDuration:0.5
                              delay:0
             usingSpringWithDamping:0.72
              initialSpringVelocity:0.8
                            options:UIViewAnimationOptionCurveEaseInOut |
                                    UIViewAnimationOptionBeginFromCurrentState
                         animations:^{
            [g_ball setCenter:CGPointMake(targetX, nc.y)];
        } completion:nil];
        g_ballRest = CGPointMake(targetX, nc.y);
    }
}

@end

static SBBallCtrl *g_ctrl = nil;

#pragma mark - 构建

static BOOL rc_buildUI(void) {
    CGRect sb = rc_screenBounds();
    UIApplication *app = [UIApplication sharedApplication];

    // ── 选宿主窗口 ──
    // 优先自建高层 window（能压过 app 自己的浮窗），失败则退化为挂到 app 的 keyWindow
    UIWindowScene *scene = rc_activeScene();
    if (!scene && app) {
        UIWindow *kw = rc_keyWindow();
        if (kw) scene = [kw windowScene];
    }

    RC(@"[UI] scene=%@ keyWindow=%@",
       scene ? NSStringFromClass([scene class]) : @"(nil)",
       rc_keyWindow() ? @"有" : @"无");

    UIWindow *hostWin = nil;

    if (scene) {
        g_window = [[SBWindow alloc] initWithWindowScene:scene];
        hostWin = g_window;
        RC(@"[UI] 用 initWithWindowScene 创建");
    } else {
        g_window = [[SBWindow alloc] initWithFrame:sb];
        hostWin = g_window;
        RC(@"[UI] 用 initWithFrame 创建（无 scene）");
    }

    if (!g_window) {
        RC(@"!! window 创建失败");
        return NO;
    }

    if (!scene) {
        // 无 scene 时自建 window 在 iOS 13+ 往往不显示，直接退化为挂在 keyWindow
        RC(@"[UI] 无 scene，改用 keyWindow 作为宿主");
        g_window = nil;
        hostWin = rc_keyWindow();
        if (!hostWin) {
            RC(@"!! keyWindow 也为空");
            return NO;
        }
    }

    UIView *hostView = nil;
    CGRect hostBounds = sb;

    if (g_window) {
        [g_window setFrame:sb];
        [g_window setWindowLevel:RC_WINDOW_LEVEL];
        [g_window setBackgroundColor:[UIColor clearColor]];

        UIViewController *vc = [[UIViewController alloc] init];
        SBPassthroughView *v = [[SBPassthroughView alloc] initWithFrame:sb];
        [v setBackgroundColor:[UIColor clearColor]];
        [vc setView:v];
        [g_window setRootViewController:vc];
        hostView = v;

        // 关键：先 makeKeyAndVisible 保证显示，再把 key 还给原窗口，避免抢焦点
        UIWindow *prevKey = rc_keyWindow();
        [g_window makeKeyAndVisible];
        if (prevKey && prevKey != g_window && [prevKey canBecomeKeyWindow]) {
            [prevKey makeKeyWindow];
            RC(@"[UI] key 已归还给原窗口");
        }
        // 再确认一次可见
        [g_window setHidden:NO];
        RC(@"[UI] 自建 window level=%.0f hidden=%d",
           (double)RC_WINDOW_LEVEL, (int)[g_window isHidden]);
    } else {
        // 挂在 app 的 keyWindow 上
        UIViewController *rvc = [hostWin rootViewController];
        UIView *base = rvc ? [rvc view] : hostWin;
        if (!base) {
            RC(@"!! keyWindow 无可用 view");
            return NO;
        }
        hostBounds = [base bounds];
        SBPassthroughView *v = [[SBPassthroughView alloc] initWithFrame:hostBounds];
        [v setBackgroundColor:[UIColor clearColor]];
        [base addSubview:v];
        [base bringSubviewToFront:v];
        hostView = v;
        RC(@"[UI] 已挂到 keyWindow，host=%.0fx%.0f",
           (double)hostBounds.size.width, (double)hostBounds.size.height);
    }

    if (!hostView) {
        RC(@"!! 宿主 view 为空");
        return NO;
    }

    sb = hostBounds;
    g_ctrl = [[SBBallCtrl alloc] init];

    // ── 悬浮球 ──
    CGFloat bs = 56;
    CGFloat bx = sb.size.width - bs - 12;
    CGFloat by = sb.size.height * 0.28;
    g_ballRest = CGPointMake(bx + bs / 2, by + bs / 2);

    g_ball = [[UIView alloc] initWithFrame:CGRectMake(bx, by, bs, bs)];
    [g_ball setCenter:g_ballRest];
    [g_ball setBackgroundColor:[UIColor colorWithRed:0.11 green:0.12 blue:0.15 alpha:0.92]];
    [[g_ball layer] setCornerRadius:bs / 2];
    [[g_ball layer] setMasksToBounds:NO];
    [[g_ball layer] setShadowColor:[[UIColor blackColor] CGColor]];
    [[g_ball layer] setShadowOpacity:0.35];
    [[g_ball layer] setShadowRadius:8];
    [[g_ball layer] setShadowOffset:CGSizeMake(0, 3)];
    [[g_ball layer] setBorderWidth:1.5];
    [[g_ball layer] setBorderColor:[[UIColor colorWithRed:0.35 green:0.78 blue:0.98 alpha:0.9] CGColor]];

    UILabel *glyph = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, bs, bs)];
    [glyph setText:@"R"];
    [glyph setTextAlignment:NSTextAlignmentCenter];
    [glyph setFont:[UIFont boldSystemFontOfSize:24]];
    [glyph setTextColor:[UIColor colorWithRed:0.35 green:0.78 blue:0.98 alpha:1]];
    [g_ball addSubview:glyph];

    UITapGestureRecognizer *tap =
        [[UITapGestureRecognizer alloc] initWithTarget:g_ctrl action:@selector(onTap:)];
    [g_ball addGestureRecognizer:tap];

    UIPanGestureRecognizer *pan =
        [[UIPanGestureRecognizer alloc] initWithTarget:g_ctrl action:@selector(onPan:)];
    [pan setCancelsTouchesInView:NO];
    [g_ball addGestureRecognizer:pan];

    [hostView addSubview:g_ball];

    // ── 面板 ──
    CGFloat pw = sb.size.width - 32;
    if (pw > 560) pw = 560;
    CGFloat ph = sb.size.height * 0.62;
    if (ph > 520) ph = 520;

    UIView *panel = [[UIView alloc] initWithFrame:CGRectMake(0, 0, pw, ph)];
    [panel setCenter:CGPointMake(sb.size.width / 2, sb.size.height / 2)];
    [panel setBackgroundColor:[UIColor colorWithRed:0.08 green:0.09 blue:0.12 alpha:0.97]];
    [[panel layer] setCornerRadius:16];
    [[panel layer] setMasksToBounds:YES];
    [panel setHidden:YES];
    [panel setAlpha:0];

    // 标题
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(16, 6, pw - 32, 22)];
    [title setText:@"StarRecon 日志"];
    [title setFont:[UIFont boldSystemFontOfSize:16]];
    [title setTextColor:[UIColor whiteColor]];
    [panel addSubview:title];

    SBUIActions *act = [[SBUIActions alloc] init];

    // 按钮行
    CGFloat bw = (pw - 44) / 4.0;
    CGFloat by2 = 32;
    [panel addSubview:rc_makeButton(@"复制", @selector(doCopy), act,
        [UIColor colorWithRed:0.18 green:0.42 blue:0.70 alpha:1],
        CGRectMake(12 + (bw + 6) * 0, by2, bw, 26))];
    [panel addSubview:rc_makeButton(@"分享", @selector(doShare), act,
        [UIColor colorWithRed:0.16 green:0.52 blue:0.34 alpha:1],
        CGRectMake(12 + (bw + 6) * 1, by2, bw, 26))];
    [panel addSubview:rc_makeButton(@"清空", @selector(doClear), act,
        [UIColor colorWithRed:0.45 green:0.32 blue:0.12 alpha:1],
        CGRectMake(12 + (bw + 6) * 2, by2, bw, 26))];
    [panel addSubview:rc_makeButton(@"关闭", @selector(doClose), act,
        [UIColor colorWithRed:0.52 green:0.18 blue:0.20 alpha:1],
        CGRectMake(12 + (bw + 6) * 3, by2, bw, 26))];

    // 文本区
    g_text = [[UITextView alloc] initWithFrame:CGRectMake(12, 66, pw - 24, ph - 78)];
    [g_text setEditable:NO];
    [g_text setSelectable:YES];
    [g_text setBackgroundColor:[UIColor colorWithRed:0.04 green:0.05 blue:0.07 alpha:1]];
    [g_text setTextColor:[UIColor colorWithRed:0.72 green:0.85 blue:0.72 alpha:1]];
    [g_text setFont:[UIFont monospacedSystemFontOfSize:10 weight:0]];
    [[g_text layer] setCornerRadius:8];
    [[g_text layer] setMasksToBounds:YES];
    [panel addSubview:g_text];

    [hostView addSubview:panel];
    g_panel = panel;

    // 只显示，不抢 key window —— makeKeyAndVisible 会夺走 app 的键盘与输入焦点
    RC(@"[UI] 悬浮球已创建 屏幕=%.0fx%.0f 位置=(%.0f,%.0f)",
       (double)sb.size.width, (double)sb.size.height,
       (double)g_ballRest.x, (double)g_ballRest.y);
    return YES;
}

#pragma mark - 安装

static int g_uiAttempts = 0;

void RCInstallUIWindow(void) {
    if (g_window || g_ball) {
        RC(@"UI 已存在，跳过");
        return;
    }
    if (g_uiAttempts >= 6) {
        RC(@"!! UI 重试 6 次仍失败，改为弹窗提示");
        // 兜底提示：让用户知道 dylib 已经加载，只是 UI 起不来
        UIApplication *app = [UIApplication sharedApplication];
        UIWindow *kw = app ? [app keyWindow] : nil;
        UIViewController *vc = kw ? [kw rootViewController] : nil;
        if (vc) {
            UIAlertController *al = [UIAlertController
                alertControllerWithTitle:@"ReconDylib 已加载"
                                 message:@"悬浮球创建失败，日志仍在写入文件。请把设备和系统版本告诉我。"
                          preferredStyle:0];
            [vc presentViewController:al animated:YES completion:nil];
        }
        return;
    }
    g_uiAttempts++;

    RCSection(@"应用内 UI");
    RC(@"第 %d 次尝试创建", g_uiAttempts);

    BOOL ok = NO;
    RC_SAFE_BEGIN
        ok = rc_buildUI();
    RC_SAFE_END

    if (!ok) {
        RC(@"创建失败，0.5s 后重试");
        RCAfterSec(0.5, ^{
            RCInstallUIWindow();
        });
        return;
    }

    if (g_refresh) [g_refresh invalidate];
    g_refresh = [NSTimer scheduledTimerWithTimeInterval:0.6
                                                 target:g_ctrl
                                               selector:@selector(doRefresh)
                                               userInfo:nil
                                                repeats:YES];
    RC(@"悬浮球就位：点开看日志，拖动可换位置");

    // 2 秒后自检：球是否真的在视图树上
    RCAfterSec(2.0, ^{
        if (!g_ball) {
            RC(@"!! 自检：球对象为空");
            return;
        }
        UIView *sp = [g_ball superview];
        RC(@"自检：ball.superview=%@ hidden=%d alpha=%.1f center=(%.0f,%.0f)",
           sp ? NSStringFromClass([sp class]) : @"(nil)",
           (int)[g_ball isHidden],
           (double)[g_ball alpha],
           (double)[g_ball center].x,
           (double)[g_ball center].y);
        if (!sp) RC(@"!! 自检：球已脱离视图树，UI 不会显示");
    });
}
