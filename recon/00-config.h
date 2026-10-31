// 00-config.h — 侦察版配置
#ifndef RECON_CONFIG_H
#define RECON_CONFIG_H

// 构建标识，日志首行打印，用于确认加载的是哪一版
#ifndef RC_CFG_BUILD_ID
#define RC_CFG_BUILD_ID "RECON-20261031"
#endif

// 日志文件名
#ifndef RC_CFG_LOG_NAME
#define RC_CFG_LOG_NAME "StarRecon.log"
#endif

// 单个日志文件上限（字节），超过后停止写入，避免写满磁盘
#ifndef RC_CFG_LOG_MAX
#define RC_CFG_LOG_MAX (4 * 1024 * 1024)
#endif

// 单条 body 最大记录长度
#ifndef RC_CFG_BODY_MAX
#define RC_CFG_BODY_MAX 8192
#endif

// 是否记录调用栈（失败文案出现时）
#ifndef RC_CFG_TRACE_STACK
#define RC_CFG_TRACE_STACK 1
#endif

// 调用栈深度
#ifndef RC_CFG_TRACE_DEPTH
#define RC_CFG_TRACE_DEPTH 16
#endif

// 目标授权类
#ifndef RC_CFG_AUTH_CLASS
#define RC_CFG_AUTH_CLASS "KQ7mV2xN9R"
#endif

// 菜单类
#ifndef RC_CFG_MENU_CLASS
#define RC_CFG_MENU_CLASS "STARSMenuView"
#endif

#endif
