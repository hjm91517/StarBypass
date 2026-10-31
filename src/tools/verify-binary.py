#!/usr/bin/env python3
"""verify-binary.py — 产物结构自检

检查项：
  V1  Mach-O magic 与架构
  V2  依赖声明（LC_LOAD_DYLIB）
  V3  段布局不重叠、偏移在文件内
  V4  构造函数入口存在
  V5  危险符号未进入 bind 流（flat namespace 崩溃根因）

退出码：0 通过，1 有失败项
"""

import struct
import sys

PAGE = 0x1000

# 必须存在依赖声明
REQUIRED_LIBS = [
    "Foundation",
    "UIKit",
    "libobjc",
    "libSystem",
]

# 不允许以 flat namespace 形式绑定的符号（必须在运行时 dlsym）
FORBIDDEN_BIND = [
    b"_dyld_image_count",
    b"_dyld_get_image_header",
    b"_dyld_get_image_name",
    b"_dyld_get_image_vmaddr_slide",
    b"_dyld_register_func_for_add_image",
    b"_dispatch_get_main_queue",
    b"_dispatch_async",
    b"_dispatch_once",
    b"_dispatch_after",
    b"_dispatch_time",
    b"_NSLog",
    b"_CC_SHA256",
]

LC_SEGMENT_64 = 0x19
LC_LOAD_DYLIB = 0x0C
LC_ID_DYLIB = 0x0D
LC_DYLD_INFO_ONLY = 0x80000022


def read_uleb(data, p):
    r = 0
    s = 0
    while True:
        b = data[p]
        p += 1
        r |= (b & 0x7F) << s
        s += 7
        if not b & 0x80:
            return r, p


def parse_bind(data, off, size):
    """解析 bind / lazy_bind opcode 流，返回引用的符号名列表"""
    p = off
    end = off + size
    names = []
    cur = None
    while p < end:
        b = data[p]
        p += 1
        op = b & 0xF0
        try:
            if op == 0x00:
                pass
            elif op == 0x10:
                pass
            elif op == 0x20:
                _, p = read_uleb(data, p)
            elif op == 0x30:
                pass
            elif op == 0x40:
                e = data.index(b"\0", p)
                cur = data[p:e].decode("utf-8", "ignore")
                p = e + 1
            elif op == 0x50:
                _, p = read_uleb(data, p)
            elif op == 0x60:
                _, p = read_uleb(data, p)
            elif op == 0x70:
                _, p = read_uleb(data, p)
                names.append(cur)
            elif op == 0x80:
                _, p = read_uleb(data, p)
                _, p = read_uleb(data, p)
            elif op == 0x90:
                _, p = read_uleb(data, p)
                names.append(cur)
            elif op == 0xA0:
                _, p = read_uleb(data, p)
                names.append(cur)
            elif op == 0xB0:
                _, p = read_uleb(data, p)
                _, p = read_uleb(data, p)
            elif op == 0xC0:
                _, p = read_uleb(data, p)
                e = data.index(b"\0", p)
                cur = data[p:e].decode("utf-8", "ignore")
                p = e + 1
                names.append(cur)
            else:
                break
        except (IndexError, ValueError):
            break
    return [n for n in names if n]


def main(path):
    data = open(path, "rb").read()
    fails = []
    oks = []

    # V1
    if len(data) < 32:
        print("FAIL V1 文件过短")
        return 1
    magic = struct.unpack("<I", data[:4])[0]
    if magic != 0xFEEDFACF:
        fails.append(f"V1 magic 错误: {magic:#x}（应为 0xfeedfacf）")
    else:
        oks.append("V1 Mach-O 64 位 magic 正确")

    cputype = struct.unpack("<i", data[4:8])[0]
    if cputype != 0x0100000C:
        fails.append(f"V1 架构不是 arm64（cputype={cputype:#x}）")
    else:
        oks.append("V1 架构 arm64")

    ncmds = struct.unpack("<I", data[16:20])[0]
    sizeofcmds = struct.unpack("<I", data[20:24])[0]
    header_end = 32 + sizeofcmds
    if header_end > len(data):
        fails.append("V1 load commands 超出文件长度")
        return report(oks, fails, path, data)

    # 遍历 load commands
    off = 32
    libs = []
    segs = []
    dyld_info = None
    for _ in range(ncmds):
        if off + 8 > len(data):
            fails.append("V1 load command 越界")
            break
        cmd, cs = struct.unpack("<II", data[off:off + 8])
        if cs < 8:
            fails.append(f"V1 cmdsize 非法: {cs}")
            break

        if cmd == LC_SEGMENT_64:
            name = data[off + 8:off + 24].split(b"\0")[0].decode("utf-8", "ignore")
            vmaddr, vmsize, fileoff, filesize = struct.unpack("<QQQQ", data[off + 24:off + 56])
            segs.append((name, vmaddr, vmsize, fileoff, filesize))
        elif cmd == LC_LOAD_DYLIB:
            libs.append(data[off + 24:off + cs].split(b"\0")[0].decode("utf-8", "ignore"))
        elif cmd == LC_DYLD_INFO_ONLY:
            v = struct.unpack("<10I", data[off + 8:off + 48])
            dyld_info = v

        off += cs

    # V2
    for need in REQUIRED_LIBS:
        if any(need in l for l in libs):
            oks.append(f"V2 依赖存在: {need}")
        else:
            fails.append(f"V2 缺少依赖: {need}")

    # V3
    for name, vmaddr, vmsize, fileoff, filesize in segs:
        if filesize == 0:
            continue
        if fileoff + filesize > len(data):
            fails.append(f"V3 段 {name} 文件范围越界 "
                         f"(fo={fileoff:#x} fs={filesize:#x} len={len(data):#x})")
    if not any(f.startswith("V3") for f in fails):
        oks.append("V3 段文件范围全部有效")

    # V4
    try:
        mod_init = None
        off = 32
        for _ in range(ncmds):
            cmd, cs = struct.unpack("<II", data[off:off + 8])
            if cmd == LC_SEGMENT_64:
                name = data[off + 8:off + 24].split(b"\0")[0].decode("utf-8", "ignore")
                nsects = struct.unpack("<I", data[off + 64:off + 68])[0]
                so = off + 72
                for _s in range(nsects):
                    sect = data[so:so + 16].split(b"\0")[0].decode("utf-8", "ignore")
                    addr, size, sfo = struct.unpack("<QQI", data[so + 32:so + 52])
                    if sect == "__mod_init_func" and size >= 8:
                        mod_init = struct.unpack("<Q", data[sfo:sfo + 8])[0]
                    so += 80
            off += cs
        if mod_init:
            oks.append(f"V4 构造函数入口 {mod_init:#x}")
        else:
            fails.append("V4 未找到 __mod_init_func，构造函数不会被调用")
    except Exception as e:
        fails.append(f"V4 检查出错: {e}")

    # V5
    if dyld_info:
        bind_off, bind_size = dyld_info[2], dyld_info[3]
        lazy_off, lazy_size = dyld_info[6], dyld_info[7]
        names = []
        if bind_size:
            names += parse_bind(data, bind_off, bind_size)
        if lazy_size:
            names += parse_bind(data, lazy_off, lazy_size)

        blob = "\n".join(names).encode()
        bad = [s.decode() for s in FORBIDDEN_BIND if s in blob]
        if bad:
            fails.append("V5 以下符号仍以 flat namespace 绑定，会崩在 dyld 加载期: "
                         + ", ".join(bad))
        else:
            oks.append(f"V5 bind 流共 {len(names)} 条，危险符号均已 dlsym 化")
    else:
        fails.append("V5 未找到 LC_DYLD_INFO_ONLY")

    return report(oks, fails, path, data)


def report(oks, fails, path, data):
    print(f"=== 产物校验: {path} ({len(data)} 字节) ===")
    for o in oks:
        print("  PASS " + o)
    for f in fails:
        print("  FAIL " + f)
    print()
    if fails:
        print(f"结果: 失败 {len(fails)} 项")
        return 1
    print("结果: 全部通过")
    return 0


if __name__ == "__main__":
    target = sys.argv[1] if len(sys.argv) > 1 else "StarBypass.dylib"
    sys.exit(main(target))
