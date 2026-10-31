// 01-shared.h — 公共基础层
// 所有模块共用的日志、配置、状态、原函数表、dispatch 与 dlsym 封装
//
// 设计原则：
//   1. 日志、dispatch、objc 运行时入口全部走 dlsym，避免 flat namespace 符号绑定
//   2. 所有 hook 入口可被 SB_SAFE_BEGIN/END 包裹，异常不冒泡
//   3. 原函数指针集中登记，取不到时安全降级

#ifndef SB_SHARED_H
#define SB_SHARED_H

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <stdint.h>
#include <stddef.h>

#include "00-config.h"

#ifdef __cplusplus
extern "C" {
#endif

#pragma mark - 日志

void SBLogLine(NSString *fmt, ...);
#define SBLog(...) SBLogLine(__VA_ARGS__)

#pragma mark - 异常包裹

#define SB_SAFE_BEGIN @try {
#define SB_SAFE_END } @catch (NSException *e) { \
    SBLog(@"exception %@: %@", [e name], [e reason]); \
} @catch (...) { SBLog(@"exception unknown"); }

#pragma mark - 配置

const char *SB_masterCardC(void);
NSString *SB_masterCard(void);
BOOL SB_acceptAny(void);          // YES：任意卡密通过
BOOL SB_overrideFailureText(void); // YES：把界面失败文案改写成成功

#pragma mark - 本地授权状态

void SB_persistAuthorized(NSString *card, NSString *expiry);
BOOL SB_localAuthorized(void);

// 判断给定对象是否等于主卡密
BOOL SB_isMaster(id obj);

#pragma mark - 原函数表

void SB_storeIMP(NSString *owner, NSString *name, IMP imp);
IMP  SB_origIMP(NSString *owner, NSString *name);

// 安装 hook 的便捷封装：自动登记原实现
BOOL SB_hookInstance(Class cls, SEL sel, IMP replacement);
BOOL SB_hookClass(Class cls, SEL sel, IMP replacement);

#pragma mark - dlsym 封装

void *SB_sym(const char *name);

#pragma mark - dispatch 封装（全部运行时解析）

typedef void *SBQueue;
typedef uint64_t SBTime;
typedef long SBOnce;

SBQueue SB_mainQueue(void);
void    SB_asyncMain(void (^blk)(void));
void    SB_afterSec(double sec, void (^blk)(void));
void    SB_once(SBOnce *pred, void (^blk)(void));

#ifdef __cplusplus
}
#endif

#endif
