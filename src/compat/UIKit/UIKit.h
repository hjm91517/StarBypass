// compat/UIKit/UIKit.h — 语法校验用最小 UIKit 声明
// 仅提供编译期需要的类型与选择器，无任何实现。
// 真机构建请用 Xcode SDK，不要引入本目录。
#ifndef SB_COMPAT_UIKIT_H
#define SB_COMPAT_UIKIT_H

#include <Foundation/Foundation.h>

@interface UIDevice : NSObject
+ (instancetype)currentDevice;
- (NSString *)systemVersion;
- (NSString *)model;
@end

@interface UIView : NSObject
@end

@interface UILabel : UIView
- (void)setText:(NSString *)text;
- (NSString *)text;
@end

@interface UITextView : UIView
- (void)setText:(NSString *)text;
- (NSString *)text;
@end

@interface UIButton : UIView
- (void)setTitle:(NSString *)title forState:(NSUInteger)state;
@end

@interface UIViewController : NSObject
@end

typedef long UIAlertControllerStyle;

@interface UIAlertController : UIViewController
+ (instancetype)alertControllerWithTitle:(NSString *)title
                                 message:(NSString *)message
                          preferredStyle:(UIAlertControllerStyle)style;
- (void)setMessage:(NSString *)message;
- (void)addAction:(id)action;
@end

#endif
