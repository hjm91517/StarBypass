#!/usr/bin/env python3
"""
给已链接的 arm64 dylib 追加 LC_LOAD_DYLIB 依赖声明。

做法：load commands 区在文件头之后，紧邻 __TEXT 的第一个节（通常从 0x4000 开始）。
      header(32) + sizeofcmds 之后到 0x4000 之间是空闲 padding，
      直接把新命令写在 sizeofcmds 后面，并更新 ncmds/sizeofcmds 即可。
      不移动任何文件内容，所有已有偏移保持有效。
"""
import struct
import sys

FREE_BASE = None   # 由脚本自动探测：第一个非 load-command 内容的文件偏移


def build_dylib_cmd(name, timestamp=2, current=0x10000, compat=0x10000):
    nb = name.encode() + b"\0"
    cmdsize = (24 + len(nb) + 7) & ~7
    pad = b"\0" * (cmdsize - 24 - len(nb))
    return struct.pack("<IIIIII", 0x0C, cmdsize, 24, timestamp, current, compat) + nb + pad


def main(path, libs):
    data = bytearray(open(path, "rb").read())

    magic, cputype, cpusub, ftype, ncmds, sizeofcmds, flags, _ = struct.unpack("<IiiIIIII", data[:32])
    if magic != 0xFEEDFACF:
        raise SystemExit("not a 64-bit Mach-O")

    header_end = 32 + sizeofcmds

    # 探测可用空间：找 __TEXT 段里第一个节的 file offset 作为上限
    limit = None
    segs = []
    off = 32
    for _ in range(ncmds):
        cmd, cs = struct.unpack("<II", data[off:off + 8])
        if cmd == 0x19:
            segname = data[off + 8:off + 24].split(b"\0")[0].decode(errors="ignore")
            vmaddr, vmsize, fileoff, filesize = struct.unpack("<QQQQ", data[off + 24:off + 56])
            nsects = struct.unpack("<I", data[off + 64:off + 68])[0]
            segs.append((segname, fileoff, filesize, nsects, off))
            if segname == "__TEXT":
                s = off + 72
                first = None
                for _s in range(nsects):
                    sectname = data[s:s + 16].split(b"\0")[0].decode(errors="ignore")
                    sect_off = struct.unpack("<I", data[s + 48:s + 52])[0]
                    if sect_off and (first is None or sect_off < first):
                        first = sect_off
                    s += 80
                if first:
                    limit = first
        off += cs

    if limit is None:
        raise SystemExit("cannot locate __TEXT first section")

    # 现有依赖
    existing = set()
    off = 32
    for _ in range(ncmds):
        cmd, cs = struct.unpack("<II", data[off:off + 8])
        if cmd in (0x0C, 0x18, 0x1F, 0x23, 0x8000001F):
            nm = data[off + 24:off + cs].split(b"\0")[0].decode(errors="ignore")
            existing.add(nm)
        off += cs

    to_add = [L for L in libs if L not in existing]
    if not to_add:
        print("all libs already present")
        return

    blob = b"".join(build_dylib_cmd(L) for L in to_add)

    if header_end + len(blob) > limit:
        raise SystemExit(
            f"not enough room: need {len(blob)} bytes, "
            f"available {limit - header_end}"
        )

    data[header_end:header_end + len(blob)] = blob
    struct.pack_into("<I", data, 16, ncmds + len(to_add))          # ncmds
    struct.pack_into("<I", data, 20, sizeofcmds + len(blob))       # sizeofcmds

    open(path, "wb").write(bytes(data))
    print(f"added {len(to_add)} dylibs, +{len(blob)} bytes in place, "
          f"total size unchanged ({len(data)})")


LIBS = [
    "/System/Library/Frameworks/Foundation.framework/Foundation",
    "/System/Library/Frameworks/UIKit.framework/UIKit",
    "/usr/lib/libobjc.A.dylib",
    "/usr/lib/libSystem.B.dylib",
]

if __name__ == "__main__":
    target = sys.argv[1] if len(sys.argv) > 1 else "StarBypass.dylib"
    main(target, LIBS)
