# FlashBytePro 注入库

对抗一个字符串全加密、控制流被 VM 平坦化的授权系统。四层接管：网络伪造、布尔接管、文案改写、检测绕过。

产物：`src/StarBypass.dylib`（arm64，115,176 字节，build `SB-20261031-DOUBLE`）

---

## 状态

| 项 | 结果 |
|---|---|
| 语法校验（8 文件） | 通过 |
| 契约一致性（K1-K4） | 通过 |
| 交叉构建 | 通过 |
| 产物结构校验（V1-V5） | 通过 |
| 危险符号绑定 | 0 条（全部 dylsm） |
| 真机运行时行为 | **待验证** |

上一版崩在 `dyld4::prepare: symbol not found in flat namespace '_dispatch_get_main_queue'`，
根因是静态绑定 + 缺 `LC_LOAD_DYLIB`。已从二进制层面消除。

---

## 先确认你跑的是新版本

启动后日志第一行必须是：

```
[StarBypass] === StarBypass 启动 build=SB-20261031-DOUBLE ===
```

没有这行 → 加载的还是旧文件，先换文件再看别的。

核对设备上的文件大小应为 **115,176 字节**。

---

## 动态逆向（第一步，最重要）

静态分析已确认：二进制里**没有明文文案、没有明文 URL**，全部运行时解密。
所以真实接口和真实失败原因只能动态抓。

```bash
cd src && frida -U -f com.shadow.h5ggapp -l tools/dynamic-recon.js
```

触发一次卡密验证，重点看：

```
[P3] → POST https://...              真实接口地址
[P3]    body: {"code":"hjnb",...}     真实请求参数
[P3]    ← 真实回包: {"code":0,...}    真实响应结构 ← 最关键
```

拿到真实回包后，按 [docs/04-dynamic-recon.md](docs/04-dynamic-recon.md) 末节的对照表改
`03-network.m` 的字段集合即可。详见该文档。

---

## 卡密

输入 **hjnb**。默认 `SB_CFG_ACCEPT_ANY=1`，任意卡密放行。
只认 hjnb：改 `src/00-config.h`

```c
#define SB_CFG_ACCEPT_ANY 0
```

---

## 四层设计

| 层 | 文件 | 做法 | 侵入性 |
|---|---|---|---|
| 诊断 | `02-diagnose.m` | 抓失败文案 + 调用栈，可改写成成功 | 无（只读/改显示） |
| 网络 | `03-network.m` | NSURLProtocol + 替换 completionHandler 数据，双保险 | 低 |
| 授权 | `04-license.m` | 只接管 BOOL 方法；void 回调保留原链改参数 | 低 |
| 对抗 | `05-detection.m` | 符号级替换代理/VPN/文件/模块检测 | 无 |

**刻意不做的事**（上一版的 bug 来源）：

- 不替换单例 `+xK7vQ2mN` —— 原实现要初始化内部状态，替换会破坏
- 不接管返回对象的方法 —— 返回类型语义不明，猜错就崩

`06-guard.m` 崩溃防护，`07-bootstrap.m` 只装配。

---

## 目录

```
.
├── README.md
├── deps.txt
├── .env.example  .gitignore
├── docs/
│   ├── 01-contracts.md         接口/配置/回包/二进制契约
│   ├── 02-architecture.md      分层设计与扩展点
│   ├── 03-verification.md      验证记录（含崩溃日志分析）
│   ├── 04-dynamic-recon.md     动态逆向方法与对照表
│   └── verify-contracts.py     契约检查器
├── assets/
│   ├── FlashBytePro.dylib      原始二进制（只读）
│   └── verify-original.py      指纹校验
└── src/
    ├── Makefile
    ├── 00-config.h             配置 + 构建标识
    ├── 01-shared.h/.m          公共基础
    ├── 02-diagnose.m           诊断
    ├── 03-network.m            网络
    ├── 04-license.m            授权
    ├── 05-detection.m          对抗
    ├── 06-guard.m              稳定
    ├── 07-bootstrap.m          装配
    ├── lib/symbol-rebind.c/.h  符号重绑定
    ├── compat/                 语法校验用最小头
    ├── tools/
    │   ├── dynamic-recon.js    动态逆向 Frida agent
    │   ├── inject-load-dylibs.py
    │   └── verify-binary.py
    └── StarBypass.dylib        产物
```

---

## 命令

```bash
cd src
make check        # 语法
make contracts    # 契约一致性
make cross        # 构建（无 SDK）
make verify       # 产物结构
make ios          # 真机构建（需 Xcode）
```

注入：

```bash
insert_dylib --inplace @executable_path/Frameworks/StarBypass.dylib Payload/App.app/App
cp src/StarBypass.dylib Payload/App.app/Frameworks/
codesign -f -s - --deep Payload/App.app
```

---

## 日志

```
=== StarBypass 启动 build=SB-20261031-DOUBLE ===
[guard] 崩溃防护已启用
[detect] 符号替换 5 项，结果 0
[net] 第一道：SBURLProtocol 已注册
[net] 第一道：configuration 注入就位
[net] 第二道：dataTaskWithRequest 已接管
授权类布尔方法接管 43 个
[net] 第一道拦截，返回伪造回包 xxx 字节
=== 装配完成 ===
```

排查顺序：build 标识 → 布尔接管数量 → 拦截日志 → `[P3] 真实回包`。

扩展方式见 [docs/02-architecture.md](docs/02-architecture.md) 第五节。
