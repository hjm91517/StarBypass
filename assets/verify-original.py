#!/usr/bin/env python3
"""verify-original.py — 参考二进制完整性校验

原始 FlashBytePro.dylib 只作逆向参考，不参与构建。
本脚本记录其指纹，防止误改。

用法：python3 assets/verify-original.py
"""

import hashlib
import os
import struct
import sys

ORIGINAL = "FlashBytePro.dylib"

# 首次确认后固化，后续任何改动都会被检出
EXPECTED_SIZE = 20665968
EXPECTED_SHA256 = "d6b44036ce5745900de4b024fa4d0fe79039951e972e380e99437f1f8e46c909"


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    path = os.path.join(here, ORIGINAL)

    if not os.path.exists(path):
        print(f"FAIL 找不到参考二进制: {path}")
        return 1

    size = os.path.getsize(path)
    digest = sha256(path)

    with open(path, "rb") as f:
        magic = struct.unpack("<I", f.read(4))[0]
        f.seek(4)
        cputype = struct.unpack("<i", f.read(4))[0]

    print(f"文件: {ORIGINAL}")
    print(f"大小: {size} 字节" + ("" if size == EXPECTED_SIZE else f"  (预期 {EXPECTED_SIZE})"))
    print(f"SHA256: {digest}")
    print(f"magic: {magic:#x}  cputype: {cputype:#x}")

    ok = True
    if magic != 0xFEEDFACF:
        print("FAIL magic 不是 64 位 Mach-O")
        ok = False
    if cputype != 0x0100000C:
        print("FAIL 架构不是 arm64")
        ok = False
    if size != EXPECTED_SIZE:
        print("WARN 大小与记录不一致")
    if EXPECTED_SHA256 and digest != EXPECTED_SHA256:
        print("FAIL SHA256 不匹配，文件已被修改")
        ok = False

    print("结果:", "通过" if ok else "失败")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
