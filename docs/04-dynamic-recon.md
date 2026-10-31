# 动态逆向（Dynamic Recon）

## 为什么必须做动态逆向

静态分析已经确认的事实（见 `03-verification.md`）：

| 静态结论 | 证据 |
|---|---|
| 二进制内**无明文中文文案** | 精确字节搜索「卡密」「不存在」「激活」「授权」「成功」全未命中，UTF-8 与 UTF-16 均无 |
| 二进制内**无明文 URL** | `http://` / `https://` 全未命中 |
| 授权类 43 个方法名全部混淆 | `KQ7mV2xN9R` 方法表，形如 `qM6tX1bW`、`zD3mV7kQ:` |
| 字符串运行时解密 | 存在 `(len, ptr)` 加密表 + 逐字节 XOR 解密序列 |

结论：**真实接口地址、真实回包结构、真实失败文案来源，静态拿不到，只能在运行时抓。**

动态逆向不是可选项，是唯一能给出 ground truth 的路径。

## 工具

`src/tools/dynamic-recon.js` —— Frida agent，四阶段取证：

| 阶段 | 作用 | 关键输出 |
|---|---|---|
| P1 环境 | 确认 ObjC 可用、目标类存在、本 dylib 是否加载 | `类 KQ7mV2xN9R: 存在` |
| P2 方法 | 枚举授权类全部方法与签名，观测无参方法返回值 | `调用 qM6tX1bW → 0` |
| P3 网络 | hook `dataTaskWithRequest:completionHandler:`，抓真实 URL / body / **真实回包** | `→ POST https://...` / `← 真实回包: {...}` |
| P4 文案 | hook `-[UILabel setText:]`，失败文案出现时打调用栈 | `=== 失败文案出现 ===` + 栈帧 |

## 用法

```bash
# 启动时挂载（推荐，能抓到首次请求）
frida -U -f com.shadow.h5ggapp -l dynamic-recon.js

# 已运行进程
frida -U -n h5ggapp -l dynamic-recon.js
```

挂载完成后触发一次卡密验证，然后按顺序读日志。

## 该看什么

### 第一优先：P3 的真实回包

```
[P3] → POST https://xxx/api/xxx
[P3]    body: {"code":"hjnb","uuid":"..."}
[P3]    ← 真实回包: {"code":0,"msg":"卡密不存在"}
```

这一段直接给出两个此前只能猜的东西：

1. **真实 URL 路径** → 用来收紧 `SB_shouldFake` 的判定，不再靠 `POST + body` 兜底
2. **真实回包字段名** → 用来修正 `SB_buildSuccessBody` 的字段集合

如果回包里是 `{"code":0,"msg":"卡密不存在"}`，就说明客户端只要看到 `code != 200` 就判定失败，
那么伪造包的 `code` 必须是服务端同款成功值（可能是 `1` 而不是 `200`）。

### 第二优先：P4 的调用栈

如果 P3 显示请求根本没发出（没有 `→` 行），说明失败来自本地逻辑。
P4 的栈帧会直接指出是哪个方法在产生文案。

### 第三优先：P2 的返回值

`调用 xxx → 0` 表示该方法是判定入口且返回失败。
`→ 1` 表示已被我们的 dylib 接管成功。两者对比可确认接管是否生效。

## 脱敏

默认对卡密/设备号脱敏（`REDACT: true`），长串只留首尾 3 字符。
排查字段格式时可临时改 `REDACT: false`。

## 抓到数据之后怎么改

| 抓到的证据 | 对应修改 |
|---|---|
| 真实 URL 路径 | `03-network.m` 的 `SB_shouldFake` 加精确匹配 |
| 真实成功回包字段 | `03-network.m` 的 `SB_buildSuccessBody` 补齐字段 |
| 成功状态码是 `1` 不是 `200` | 同时写 `code: @1` 和 `code: @200` 两个版本 |
| 失败来自本地方法 | `04-license.m` 对准该方法加精确 hook |
| 需要看类结构 | `02-diagnose.m` 的 `SB_dumpClass` 已实现 |

## 附：本地静态模拟器

除了设备上的 Frida，本项目还用过一套 ARM64 解释器对授权方法做符号执行（可离线复现判定逻辑）。
那不是交付物，属于一次性分析手段；结论已写进 `03-verification.md`。
