# compat/ — 语法校验用的最小头文件

这些头文件**不是**产品的一部分，只在没有 iOS SDK 的环境里做语法检查时使用。
真机构建（`make ios`）用的是 Xcode 的官方 SDK，完全不需要这里的任何东西。

## 为什么存在

`make check` 在没有 macOS / Xcode 的机器上也要能跑，所以补了一批最小声明：
`Foundation`、`objc/runtime`、`mach-o/*`、`sys/statfs`、`CommonCrypto` 等。
它们只提供编译期需要的类型和函数原型，没有任何实现。

## 目录对应

| 路径 | 对应真实头 |
|---|---|
| `Foundation/Foundation.h` | Foundation 框架（最小子集） |
| `objc/runtime.h` · `objc/message.h` | Objective-C 运行时 |
| `mach-o/loader.h` · `nlist.h` · `dyld.h` · `getsect.h` | Mach-O 结构 |
| `mach/mach.h` | `vm_protect` · `mach_task_self` |
| `CommonCrypto/CommonDigest.h` | `CC_SHA256` |
| `sys/statfs.h` · `sys/mount.h` | 文件系统信息 |
| `ifaddrs.h` · `net/if.h` | 网络接口枚举 |
| `os/lock.h` | `os_unfair_lock` |
| `signal.h` · `setjmp.h` · `pthread.h` | 崩溃防护用 |
| `dlfcn.h` | `dlsym` · `RTLD_DEFAULT` |
| `std*.h` · `string.h` | 标准 C 库 |

## 注意

- **不要**在真机构建里引用这些，会跟官方 SDK 冲突。
- 修改源码后跑 `make check` 验证语法即可，不需要它们参与链接。
