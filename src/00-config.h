// 00-config.h — 全局配置
//
// 所有可调项集中在此，代码中不出现魔法值。
// 可用编译参数覆盖，例如：
//   -DSB_CFG_ACCEPT_ANY=0

#ifndef SB_CONFIG_H
#define SB_CONFIG_H

// ── 卡密 ─────────────────────────────────────────────
// 主卡密，命中即授权
#ifndef SB_CFG_MASTER_CARD
#define SB_CFG_MASTER_CARD "hjnb"
#endif

// 1 = 任意卡密通过；0 = 只认主卡密
#ifndef SB_CFG_ACCEPT_ANY
#define SB_CFG_ACCEPT_ANY 1
#endif

// 1 = 把界面失败提示改写成成功；0 = 只记录不改写
#ifndef SB_CFG_OVERRIDE_FAILURE_TEXT
#define SB_CFG_OVERRIDE_FAILURE_TEXT 1
#endif

// ── 授权展示 ─────────────────────────────────────────
// 伪造的到期时间
#ifndef SB_CFG_EXPIRY
#define SB_CFG_EXPIRY "2099-12-31 23:59:59"
#endif

// 改写后显示给用户的成功文案
#ifndef SB_CFG_SUCCESS_TEXT
#define SB_CFG_SUCCESS_TEXT "已授权 · 永久有效"
#endif

// ── 构建标识 ─────────────────────────────────────────
// 启动时打印，用于确认设备上加载的是哪一版
#ifndef SB_CFG_BUILD_ID
#define SB_CFG_BUILD_ID "SB-20261031-DOUBLE"
#endif

// ── 诊断 ─────────────────────────────────────────────
// 1 = 打印调用栈；0 = 安静模式
#ifndef SB_CFG_TRACE_STACK
#define SB_CFG_TRACE_STACK 1
#endif

// 调用栈最多打印几层
#ifndef SB_CFG_TRACE_DEPTH
#define SB_CFG_TRACE_DEPTH 24
#endif

// ── 卡密提交 hook ────────────────────────────────────
// UI 起来后延迟多久补挂 hook（秒）
#ifndef SB_CFG_REHOOK_DELAY
#define SB_CFG_REHOOK_DELAY 1.5
#endif

// ── 目标识别 ─────────────────────────────────────────
// 卡密验证所在的类
#ifndef SB_CFG_AUTH_CLASS
#define SB_CFG_AUTH_CLASS "KQ7mV2xN9R"
#endif

// 菜单视图类
#ifndef SB_CFG_MENU_CLASS
#define SB_CFG_MENU_CLASS "STARSMenuView"
#endif

#endif
