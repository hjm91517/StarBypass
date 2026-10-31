// compat/UIKit/UIKit.h — 语法校验与交叉构建用的最小 UIKit 声明
// 只提供编译期类型与选择器签名，无任何实现。
// 真机构建请用 Xcode SDK，不要引入本目录。
#ifndef SB_COMPAT_UIKIT_H
#define SB_COMPAT_UIKIT_H

#include <Foundation/Foundation.h>

#pragma mark - CoreGraphics 基础类型

typedef double CGFloat;

typedef struct { CGFloat x, y; } CGPoint;
typedef struct { CGFloat width, height; } CGSize;
typedef struct { CGPoint origin; CGSize size; } CGRect;

static inline CGPoint CGPointMake(CGFloat x, CGFloat y) {
    CGPoint p; p.x = x; p.y = y; return p;
}
static inline CGSize CGSizeMake(CGFloat w, CGFloat h) {
    CGSize s; s.width = w; s.height = h; return s;
}
static inline CGRect CGRectMake(CGFloat x, CGFloat y, CGFloat w, CGFloat h) {
    CGRect r; r.origin.x = x; r.origin.y = y; r.size.width = w; r.size.height = h;
    return r;
}
static inline CGPoint CGPointZero_(void) { return CGPointMake(0, 0); }

#define CGPointZero CGPointMake(0, 0)
#define CGSizeZero  CGSizeMake(0, 0)
#define CGRectZero  CGRectMake(0, 0, 0, 0)

#pragma mark - 基础控件

@class CALayer, UIColor, UIFont, UIWindow, UIWindowScene, UIScreen;
@class UIGestureRecognizer, UIPanGestureRecognizer, UITapGestureRecognizer;
@class UIScrollView, UIViewController, UIImage, UIPasteboard;

@interface CALayer : NSObject
- (void)setCornerRadius:(CGFloat)r;
- (void)setMasksToBounds:(BOOL)b;
- (void)setShadowColor:(void *)c;
- (void)setShadowOpacity:(float)o;
- (void)setShadowOffset:(CGSize)s;
- (void)setShadowRadius:(CGFloat)r;
- (void)setBorderWidth:(CGFloat)w;
- (void)setBorderColor:(void *)c;
@end

@interface UIColor : NSObject
+ (UIColor *)colorWithRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a;
+ (UIColor *)colorWithWhite:(CGFloat)w alpha:(CGFloat)a;
+ (UIColor *)clearColor;
+ (UIColor *)whiteColor;
+ (UIColor *)blackColor;
+ (UIColor *)systemBlueColor;
+ (UIColor *)systemRedColor;
+ (UIColor *)systemGreenColor;
+ (UIColor *)lightGrayColor;
- (void *)CGColor;
@end

@interface UIFont : NSObject
+ (UIFont *)systemFontOfSize:(CGFloat)s;
+ (UIFont *)boldSystemFontOfSize:(CGFloat)s;
+ (UIFont *)monospacedSystemFontOfSize:(CGFloat)s weight:(CGFloat)w;
@end

@interface UIView : NSObject
- (instancetype)initWithFrame:(CGRect)f;
- (void)setFrame:(CGRect)f;
- (CGRect)frame;
- (void)setBounds:(CGRect)b;
- (CGRect)bounds;
- (void)setCenter:(CGPoint)c;
- (CGPoint)center;
- (void)setBackgroundColor:(UIColor *)c;
- (void)setAlpha:(CGFloat)a;
- (CGFloat)alpha;
- (void)setHidden:(BOOL)h;
- (BOOL)isHidden;
- (CALayer *)layer;
- (void)addSubview:(UIView *)v;
- (void)removeFromSuperview;
- (void)bringSubviewToFront:(UIView *)v;
- (void)setClipsToBounds:(BOOL)b;
- (void)setUserInteractionEnabled:(BOOL)b;
- (void)addGestureRecognizer:(UIGestureRecognizer *)g;
- (void)setAutoresizingMask:(NSUInteger)m;
- (CGPoint)convertPoint:(CGPoint)p fromView:(UIView *)v;
- (void)layoutIfNeeded;
- (void)setNeedsLayout;
- (void)setContentMode:(long)m;
- (void)setTag:(long)t;
- (long)tag;
- (UIView *)hitTest:(CGPoint)p withEvent:(id)e;
@end

#pragma mark - 具体控件

typedef NSUInteger UIControlState;
typedef NSUInteger UIControlEvents;
typedef long UIButtonType;
typedef long UITextAlignment;
typedef long NSLineBreakMode;

@interface UILabel : UIView
- (void)setText:(NSString *)t;
- (NSString *)text;
- (void)setFont:(UIFont *)f;
- (void)setTextColor:(UIColor *)c;
- (void)setTextAlignment:(UITextAlignment)a;
- (void)setNumberOfLines:(NSInteger)n;
- (void)setLineBreakMode:(NSLineBreakMode)m;
@end

@interface UIButton : UIView
+ (instancetype)buttonWithType:(UIButtonType)t;
- (void)setTitle:(NSString *)t forState:(UIControlState)s;
- (void)setTitleColor:(UIColor *)c forState:(UIControlState)s;
- (void)setBackgroundColor:(UIColor *)c;
- (void)addTarget:(id)target action:(SEL)a forControlEvents:(UIControlEvents)e;
- (UILabel *)titleLabel;
@end

@interface UIScrollView : UIView
- (void)setContentSize:(CGSize)s;
- (CGSize)contentSize;
- (void)setContentOffset:(CGPoint)p;
- (void)setScrollEnabled:(BOOL)b;
- (void)setShowsVerticalScrollIndicator:(BOOL)b;
@end

@interface UITextView : UIScrollView
- (void)setText:(NSString *)t;
- (NSString *)text;
- (void)setFont:(UIFont *)f;
- (void)setTextColor:(UIColor *)c;
- (void)setEditable:(BOOL)b;
- (void)setSelectable:(BOOL)b;
- (void)setTextAlignment:(UITextAlignment)a;
@end

#pragma mark - 手势

typedef long UIGestureRecognizerState;

@interface UIGestureRecognizer : NSObject
- (instancetype)initWithTarget:(id)t action:(SEL)a;
- (UIGestureRecognizerState)state;
- (void)setCancelsTouchesInView:(BOOL)b;
@end

@interface UIPanGestureRecognizer : UIGestureRecognizer
- (CGPoint)translationInView:(UIView *)v;
- (void)setTranslation:(CGPoint)t inView:(UIView *)v;
- (CGPoint)locationInView:(UIView *)v;
- (CGPoint)velocityInView:(UIView *)v;
@end

@interface UITapGestureRecognizer : UIGestureRecognizer
- (void)setNumberOfTapsRequired:(NSUInteger)n;
@end

#pragma mark - Window / Scene / Application

typedef CGFloat UIWindowLevel;

@interface UIScene : NSObject
@end

@interface UIWindowScene : UIScene
@end

@interface UIScreen : NSObject
+ (UIScreen *)mainScreen;
- (CGRect)bounds;
- (CGFloat)scale;
@end

@interface UIWindow : UIView
- (instancetype)initWithFrame:(CGRect)f;
- (instancetype)initWithWindowScene:(UIWindowScene *)s;
- (void)setWindowLevel:(UIWindowLevel)l;
- (UIWindowLevel)windowLevel;
- (void)setRootViewController:(UIViewController *)c;
- (UIViewController *)rootViewController;
- (void)makeKeyAndVisible;
- (void)setHidden:(BOOL)h;
- (BOOL)isKeyWindow;
- (BOOL)canBecomeKeyWindow;
- (UIView *)hitTest:(CGPoint)p withEvent:(id)e;
@end

@interface UIViewController : NSObject
- (UIView *)view;
- (void)setView:(UIView *)v;
- (void)presentViewController:(UIViewController *)c
                     animated:(BOOL)an
                   completion:(void (^)(void))done;
- (void)dismissViewControllerAnimated:(BOOL)an
                           completion:(void (^)(void))done;
@end

@interface UIApplication : NSObject
+ (UIApplication *)sharedApplication;
- (NSArray *)connectedScenes;
- (id)keyWindow;
@end

#pragma mark - 其他

@interface UIPasteboard : NSObject
+ (UIPasteboard *)generalPasteboard;
- (void)setString:(NSString *)s;
@end

@interface UIActivityViewController : UIViewController
- (instancetype)initWithActivityItems:(NSArray *)items
                 applicationActivities:(NSArray *)acts;
@end

@interface UIDevice : NSObject
+ (instancetype)currentDevice;
- (NSString *)systemVersion;
- (NSString *)model;
@end

#pragma mark - 动画

typedef NSUInteger UIViewAnimationOptions;

@interface UIView (Animation)
+ (void)animateWithDuration:(double)d
                 animations:(void (^)(void))a;
+ (void)animateWithDuration:(double)d
                 animations:(void (^)(void))a
                 completion:(void (^)(BOOL))c;
+ (void)animateWithDuration:(double)d
                      delay:(double)delay
     usingSpringWithDamping:(CGFloat)damping
      initialSpringVelocity:(CGFloat)v
                    options:(UIViewAnimationOptions)o
                 animations:(void (^)(void))a
                 completion:(void (^)(BOOL))c;
@end

#define UIViewAnimationOptionCurveEaseInOut (7 << 16)
#define UIViewAnimationOptionAllowUserInteraction (1 << 1)
#define UIViewAnimationOptionBeginFromCurrentState (1 << 2)

#define UIWindowLevelNormal 0.0
#define UIWindowLevelAlert 2000.0
#define UIWindowLevelStatusBar 1000.0

#define UIControlStateNormal 0
#define UIControlStateHighlighted 1
#define UIControlEventTouchUpInside (1 << 6)

#define UIButtonTypeCustom 0
#define UIButtonTypeSystem 1

#define NSTextAlignmentLeft 0
#define NSTextAlignmentCenter 1
#define NSTextAlignmentRight 2

#define NSLineBreakByTruncatingTail 4

#define UIGestureRecognizerStateBegan 1
#define UIGestureRecognizerStateChanged 2
#define UIGestureRecognizerStateEnded 3
#define UIGestureRecognizerStateCancelled 4

#define UIViewAutoresizingFlexibleWidth  (1 << 1)
#define UIViewAutoresizingFlexibleHeight (1 << 4)

#endif
