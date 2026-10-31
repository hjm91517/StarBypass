# 分层设计（Architecture）

## 一、为什么这样分层

这个项目的本质是**在一个不透明的二进制里抢控制权**。抢控制权的地方有四类，彼此失效原因不同，所以必须分开：

| 层 | 抢什么 | 失效原因独立于其他层 |
|---|---|---|
| 诊断 | 观测：看清真实调用路径 | 只读，不会失效 |
| 网络 | 服务器回包 | 服务器改了字段就失效 |
| 授权 | 本地判定 | 方法名变了就失效 |
| 对抗 | 环境检测 | 检测点增删就失效 |

四层互不依赖，任一层失效不影响其他层，这是把模块拆开的核心理由，而非为了好看。

## 二、目录树与职责

```
/workspace
├── README.md                  项目总览与使用
├── deps.txt                   依赖清单
├── .env.example               构建环境变量示例
├── .gitignore                 忽略规则
├── docs/
│   ├── 01-contracts.md        契约（接口/配置/回包/二进制）
│   ├── 02-architecture.md     本文件：分层与目录职责
│   └── 03-verification.md     验证记录与证据
├── assets/
│   ├── FlashBytePro.dylib     原始二进制（只读参考，不参与构建）
│   └── verify-original.py     原始二进制指纹校验
└── src/
    ├── Makefile               构建入口
    ├── 00-config.h            配置，唯一调参入口
    ├── 01-shared.h/.m         公共基础层
    ├── 02-diagnose.m          诊断层
    ├── 03-network.m           网络层
    ├── 04-license.m           授权层
    ├── 05-detection.m         对抗层
    ├── 06-guard.m             稳定层
    ├── 07-bootstrap.m         装配层
    ├── lib/
    │   └── symbol-rebind.c/.h 独立库：符号重绑定
    ├── compat/                语法校验用最小头（真机构建不需要）
    ├── tools/
    │   ├── inject-load-dylibs.py  注入 LC_LOAD_DYLIB
    │   └── verify-binary.py       产物结构校验
    ├── build/                 中间产物（gitignored）
    └── StarBypass.dylib       交付产物
```

## 三、依赖方向

```
                07-bootstrap
                     │
      ┌──────┬───────┼───────┬──────┐
      ▼      ▼       ▼       ▼      ▼
   02-diag 03-net  04-lic  05-det  06-guard
      │      │       │       │      │
      └──────┴───┬───┴───────┘      │
                 ▼                  │
            01-shared ◄─────────────┘
                 │
                 ▼
              lib/（仅 05 使用）
```

规则：

- **禁止反向**：`01` 不 import 任何上层模块
- **禁止横跳**：`02` 不直接调 `04`
- **装配集中**：只有 `07` 调用各层 `SB_install*`，其他模块互不调用安装函数

## 四、关键设计决策

### 4.1 为什么拦截用 NSURLProtocol 而不是 hook dataTask

`NSURLSession` 有两条数据通路：

- `dataTaskWithRequest:completionHandler:` → 走 block
- `sessionWithConfiguration:delegate:` + `dataTaskWithRequest:` → 走 delegate

hook 前者会漏掉后者。`NSURLProtocol` 在协议层，两条路都经过，且是苹果官方机制。

### 4.2 为什么布尔方法按返回类型接管，而不是列名单

授权类有 43 个混淆方法。手写名单必然漏，且下次版本更新名单就错。
遍历 `class_copyMethodList`，凡返回类型编码首字符为 `B`（BOOL）或 `c`（char）的一律换成恒 YES——数量级正确，且无需维护。

需要返回对象的方法（过期时间、卡密提交结果）签名不同，单独精确 hook。

### 4.3 为什么危险符号必须 dlsym

系统库不导出 `_dyld_*`；`libdispatch` 在新版 iOS 中可能尚未注册到 flat namespace。
静态绑定的结果就是 `dyld4::prepare` 阶段 `symbol not found` 直接 abort——进程还没起来就死了。

全部改成运行时 `dlsym` 后，解析推迟到各库就绪之后，且失败可降级。

### 4.4 为什么链接时用 `-no_fixup_chains`

`LC_DYLD_CHAINED_FIXUPS` 的 `dataoff` 指向 `__LINKEDIT` 内部，手工 patch 后头部字段会错位（实测解析出 `version=1398735104` 这种垃圾值）。
改用传统 `LC_DYLD_INFO_ONLY` rebase/bind opcode 流，结构简单、可校验、能解析。

## 五、扩展点

| 要加什么 | 加在哪 | 怎么加 |
|---|---|---|
| 新的卡密/配置项 | `00-config.h` | 加宏 → 在 `01-shared.m` 暴露 getter |
| 新的授权方法接管 | `04-license.m` | 若返回 BOOL 会自动覆盖；否则加一个精确 hook 函数 |
| 新的环境检测绕过 | `05-detection.m` | 往 `kBadModules` / `kBadPaths` 加条目，或加新的符号替换项 |
| 新的伪造回包字段 | `03-network.m` 的 `SB_buildSuccessBody` | 往 `inner` 或 `root` 字典加键 |
| 新的显示入口拦截 | `02-diagnose.m` | 仿照 UILabel 的 hook 写一个，在 `SB_installDiagnose` 里挂上 |
| 换目标 app | `00-config.h` | 改 `SB_CFG_AUTH_CLASS` / `SB_CFG_MENU_CLASS` |
| 加新的构建目标 | `src/Makefile` | 仿 `cross` 目标写一个 |
