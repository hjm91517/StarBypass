# ReconDylib — 侦察版注入库

阶段一产物。**纯观测，不改任何业务行为**：只把运行时真实数据写进日志文件。

存在理由：静态分析已确认原 dylib 里没有明文文案、没有明文 URL，全部运行时解密。
真实接口、真实回包字段、"卡密不存在"的产生位置，只能动态取。

产物：`ReconDylib.dylib`（arm64，113,512 字节）

---

## 装法

和绕过版完全一样，二选一：

```bash
# 越狱：放进 app 的 Frameworks/
insert_dylib --inplace @executable_path/Frameworks/ReconDylib.dylib Payload/App.app/App

# 非越狱重签
insert_dylib --inplace @executable_path/Frameworks/ReconDylib.dylib Payload/App.app/App
cp ReconDylib.dylib Payload/App.app/Frameworks/
codesign -f -s - --deep Payload/App.app
```

**不要和 StarBypass.dylib 同时装**——两个都会 hook 同一批方法，互相覆盖，数据会乱。
先卸掉 StarBypass 再装这个。

---

## 用法

1. 装好后启动 app
2. 触发一次卡密验证：随便输个卡密，点激活
3. 看到提示后，再等 3 秒
4. 把日志文件取出

---

## 日志在哪

启动时会打印绝对路径，同时按顺序尝试三个位置：

| 优先 | 路径 | 取法 |
|---|---|---|
| 1 | `/var/mobile/Documents/StarRecon.log` | Filza 直接打开 |
| 2 | `<App沙盒>/Documents/StarRecon.log` | Filza 进入 app 数据目录 |
| 3 | `<App沙盒>/tmp/StarRecon.log` | 同上 |

日志首行会写明实际落盘位置：

```
[..] 日志文件: /var/mobile/Documents/StarRecon.log
```

上限 4 MB，超过停止写入，不会写满磁盘。

---

## 日志里会有什么

### ① 会话头

```
──────── 侦察会话开始 ────────
构建: RECON-20261031
应用: h5ggapp (com.shadow.h5ggapp)
版本: 5.9 build 1
系统: 26.7.1
机型: iPad
日志文件: /var/mobile/Documents/StarRecon.log
```

### ② 授权类方法表（这是阶段二最需要的）

```
-[KQ7mV2xN9R] 共 43 个方法
   -[KQ7mV2xN9R qM6tX1bW] enc=B16@0:8 args=2
   -[KQ7mV2xN9R zD3mV7kQ:] enc=B24@0:8@16 args=3
   ...
```

带完整类型编码和参数个数。阶段二据此判断哪些能安全替换。

### ③ 网络明文（最关键）

```
[REQ] → POST https://真实域名/api/xxx
[REQ]   请求头: {...}
[REQ]   请求体(64字节):
{
  "code" : "hjnb",
  "uuid" : "..."
}
[REQ] ← HTTP 200
[REQ]   响应头: {...}
[REQ]   响应体(48字节):
{
  "code" : 0,
  "msg" : "卡密不存在"
}
```

**这一段直接给出真实 URL 和真实回包字段名**，阶段二不用再猜。

### ④ 方法调用追踪

```
   → zD3mV7kQ:
   ← zD3mV7kQ: = NO
   ★ hV8nD3sJ:success:message:expiry: success=0 message=卡密不存在 expiry=(nil)
```

能看出是哪个判定方法返回 NO。

### ⑤ 失败文案来源（带调用栈）

```
★★★ 命中文案 [UILabel]: "卡密不存在"
      #0 UIKitCore ...
      #1 FlashBytePro ...
      #2 FlashBytePro ...
★★★ 调用栈结束
```

栈帧里的 `FlashBytePro` 地址就是产生该文案的方法，阶段二据此定位。

---

## 要我什么

把 `StarRecon.log` 整个发我，重点这几段：

1. `──────── 侦察会话开始` 到 `────────` 结束（确认环境）
2. `-[KQ7mV2xN9R] 共` 那一段（方法表）
3. 所有 `[REQ]` 开头的行（真实接口与回包）
4. 所有 `★★★ 命中文案` 段落（失败来源）

日志太长的话，至少给我第 3、4 类。

---

## 它做了什么 / 没做什么

| 做了 | 没做 |
|---|---|
| 记录请求与响应全文 | 不改请求 |
| 记录方法调用与原返回值 | 不改返回值 |
| 记录界面文案与调用栈 | 不改文案 |
| 隐藏自身模块名（`_dyld_get_image_name`） | 不阻断网络 |
| 绕过代理 / VPN / 文件 / 越狱探测 | 不需要装证书、不需要配代理 |

**不需要抓包工具**。数据在进程内就已经是明文，直接记录，所以不触发任何抓包检测路径。

---

## 构建

```bash
cd recon
make check     # 语法
make cross     # 交叉构建
make verify    # 产物校验
make ios       # 真机构建（需 Xcode）
```

复用 `../src/compat` 头与 `../src/lib/symbol-rebind.c`，不复制代码。
