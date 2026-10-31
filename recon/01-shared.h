// 01-shared.h — 侦察版公共层
#ifndef RECON_SHARED_H
#define RECON_SHARED_H

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <stdint.h>
#include <stddef.h>

#include "00-config.h"

#ifdef __cplusplus
extern "C" {
#endif

#pragma mark - 日志（同时输出 NSLog 与文件）

void RCLog(NSString *fmt, ...);
#define RC(...) RCLog(__VA_ARGS__)

// 分段日志，便于阅读
void RCSection(NSString *title);

// 日志文件绝对路径（用于告知用户去哪里取）
NSString *RCLogPath(void);

// 启动时探测可写路径并确认
BOOL RCOpenLog(void);

// 强制刷盘
void RCFlush(void);

// 内存日志快照（供应用内面板显示，与文件日志内容一致）
NSString *RCMemLogSnapshot(void);

// 清空内存日志（同时清空文件）
void RCMemLogClear(void);

#pragma mark - 异常包裹

#define RC_SAFE_BEGIN @try {
#define RC_SAFE_END } @catch (NSException *e) { \
    RC(@"!! 异常 %@: %@", [e name], [e reason]); \
} @catch (...) { RC(@"!! 未知异常"); }

#pragma mark - dlsym / dispatch

void *RCSym(const char *name);

typedef void *RCQueue;
typedef uint64_t RCTime;
typedef long RCOnce;

RCQueue RCMainQueue(void);
void    RCAsyncMain(void (^blk)(void));
void    RCAfterSec(double sec, void (^blk)(void));
void    RCDoOnce(RCOnce *pred, void (^blk)(void));

#pragma mark - 原函数表 + hook

void RCStoreIMP(NSString *owner, NSString *name, IMP imp);
IMP  RCOrigIMP(NSString *owner, NSString *name);

// 安装 hook，返回 YES 表示成功；自动登记原实现
BOOL RCHookInstance(Class cls, SEL sel, IMP replacement);
BOOL RCHookClass(Class cls, SEL sel, IMP replacement);

#pragma mark - 工具

// NSData → 可读字符串（UTF-8 优先，二进制转 base64 截断）
NSString *RCDataToText(NSData *data);

// 对象 → 描述字符串（安全，不抛异常）
NSString *RCDescribe(id obj);

// 调用栈字符串数组
NSArray *RCCallStack(NSUInteger depth);

#ifdef __cplusplus
}
#endif

#endif
