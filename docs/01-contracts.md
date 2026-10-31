# 契约（Contracts）

实现之前先冻结的接口约定。所有模块实现必须服从本文件，不得反向修改契约。

---

## 一、模块契约

依赖方向严格单向：`07 → 02..06 → 01`，`05 → lib`。禁止反向引用。

### 01-shared（公共基础层）

| 符号 | 签名 | 语义 |
|---|---|---|
| `SBLog` | `void SBLog(NSString *fmt, ...)` | 统一日志，前缀 `[StarBypass]`；内部走 dlsym 的 NSLog |
| `SB_sym` | `void *SB_sym(const char *name)` | dlsym 封装，失败返回 NULL |
| `SB_masterCard` | `NSString *SB_masterCard(void)` | 主卡密，取自 `SB_CFG_MASTER_CARD` |
| `SB_acceptAny` | `BOOL SB_acceptAny(void)` | 是否接受任意卡密 |
| `SB_overrideFailureText` | `BOOL SB_overrideFailureText(void)` | 是否改写失败文案 |
| `SB_isMaster` | `BOOL SB_isMaster(id obj)` | 判断对象是否为已配置主卡密，输入做 trim + 小写 |
| `SB_persistAuthorized` | `void SB_persistAuthorized(NSString *card, NSString *expiry)` | 写入全部常见授权键；`nil` 走默认值 |
| `SB_localAuthorized` | `BOOL SB_localAuthorized(void)` | 读任意一个授权键为真即返回 YES |
| `SB_storeIMP` | `void SB_storeIMP(NSString *owner, NSString *name, IMP imp)` | 登记原实现，同名只登记一次 |
| `SB_origIMP` | `IMP SB_origIMP(NSString *owner, NSString *name)` | 取回原实现，不存在返回 NULL |
| `SB_hookInstance` | `BOOL SB_hookInstance(Class, SEL, IMP)` | 替换实例方法，自动登记原实现；失败返回 NO |
| `SB_hookClass` | `BOOL SB_hookClass(Class, SEL, IMP)` | 同上，类方法 |
| `SB_mainQueue` / `SB_asyncMain` / `SB_afterSec` / `SB_once` | 见头文件 | dispatch 封装，全部运行时解析 |

**约定**：`SB_hook*` 幂等；重复调用不重复登记原实现。

### 02-diagnose（诊断层）

| 符号 | 签名 | 语义 |
|---|---|---|
| `SB_installDiagnose` | `void SB_installDiagnose(void)` | 安装显示层 hook 并 dump 目标类 |
| `SB_isFailureText` | `BOOL SB_isFailureText(NSString *)` | 失败文案判定：含失败关键词且不含成功关键词 |
| `SB_dumpClass` | `void SB_dumpClass(NSString *)` | 打印类方法清单 |

侧效：失败文案出现时打印调用栈（最多 `SB_CFG_TRACE_DEPTH` 层）；开启改写时把文案换成 `SB_CFG_SUCCESS_TEXT` 并写授权。

### 03-network（网络层）

| 符号 | 签名 | 语义 |
|---|---|---|
| `SB_installNetwork` | `void SB_installNetwork(void)` | 注册 `SBURLProtocol` 并 hook 配置工厂 |

拦截判定（顺序）：
1. 已处理过的请求 → 放行（防递归）
2. `POST` 且 body 非空 → 拦
3. URL 含授权关键词 → 拦
4. 其余 → 放行

回包契约见第三节。

### 04-license（授权层）

| 符号 | 签名 | 语义 |
|---|---|---|
| `SB_installLicense` | `void SB_installLicense(void)` | 接管授权类 |

接管规则：遍历 `SB_CFG_AUTH_CLASS` 的方法表，返回类型编码首字符为 `B` 或 `c` 的全部换成恒 YES。

### 05-detection（对抗层）

| 符号 | 签名 | 语义 |
|---|---|---|
| `SB_installDetection` | `void SB_installDetection(void)` | 符号级替换 5 个探测点 |

### 06-guard（稳定层）

| 符号 | 签名 | 语义 |
|---|---|---|
| `SB_installGuard` | `void SB_installGuard(void)` | 未捕获异常 + SIGPIPE 处理，幂等 |

### 07-bootstrap（装配层）

仅含构造函数。按 `guard → detection → network → license → diagnose` 顺序安装，UI 就绪后延迟补挂一次。**不含任何业务逻辑。**

### lib/symbol-rebind（独立库）

| 符号 | 签名 | 语义 |
|---|---|---|
| `SB_rebind_symbols` | `int SB_rebind_symbols(struct sb_rebinding[], size_t)` | 替换已加载镜像的符号指针；幂等；返回 0 成功 |

---

## 二、配置契约

全部配置在 `00-config.h`，可用 `-D` 覆盖：

| 宏 | 默认 | 含义 |
|---|---|---|
| `SB_CFG_MASTER_CARD` | `"hjnb"` | 主卡密 |
| `SB_CFG_ACCEPT_ANY` | `1` | 任意卡密通过 |
| `SB_CFG_OVERRIDE_FAILURE_TEXT` | `1` | 改写失败文案 |
| `SB_CFG_EXPIRY` | `"2099-12-31 23:59:59"` | 伪造到期时间 |
| `SB_CFG_SUCCESS_TEXT` | `"已授权 · 永久有效"` | 改写后的展示文案 |
| `SB_CFG_TRACE_STACK` | `1` | 打印调用栈 |
| `SB_CFG_TRACE_DEPTH` | `24` | 栈深 |
| `SB_CFG_REHOOK_DELAY` | `1.5` | 补挂延迟（秒） |
| `SB_CFG_AUTH_CLASS` | `"KQ7mV2xN9R"` | 授权类名 |
| `SB_CFG_MENU_CLASS` | `"STARSMenuView"` | 菜单类名 |

---

## 三、回包契约

伪造的成功回包固定为 HTTP 200，`Content-Type: application/json`。

同时提供下列键，客户端读任一都能取到值：

- 状态：`code=200`、`status=200`、`errcode=0`、`errno=0`、`success=true`、`result=true`、`ok=true`
- 文案：`msg`、`message`、`info` = `"激活成功"`
- 授权：`expiry`/`expire`/`expireTime`/`endTime` = `SB_CFG_EXPIRY`
- 会员：`vip`/`isVip` = true，`vipLevel`/`level` = 99，`status`/`state`/`type` = 1
- 卡密：`code`/`card`/`kami`
- 签名：`sign`/`checkSign`/`token`，值为 `SHA256(card + uuid + expiry)` 的十六进制
- 嵌套：完整字段同时放在 `data`、`result_data`、`info_data`

---

## 四、二进制契约

产物必须满足（由 `make verify` 强制检查）：

1. Mach-O 64 位、arm64
2. 含 4 条 `LC_LOAD_DYLIB`：Foundation / UIKit / libobjc / libSystem
3. 所有段文件范围在文件内
4. 存在 `__mod_init_func` 且指向构造函数
5. bind 流中不得出现 `_dyld_*`、`_dispatch_*`、`_NSLog`、`_CC_SHA256`

第 5 条是硬约束：这些符号必须运行时 dlsym 解析，否则会崩在 `dyld4::prepare` 阶段。
