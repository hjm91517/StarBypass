#!/usr/bin/env python3
"""verify-contracts.py — 契约一致性检查器

配合 docs/01-contracts.md 使用，确保「契约先行」不是口号：
代码必须服从契约，而不是写完再补文档。

检查项：
  K1  01-shared.h 里声明的每个函数都有实现
  K2  各模块导出的 SB_install* 都被 07-bootstrap.m 调用
  K3  00-config.h 里定义的每个配置宏都被实际用到
  K4  模块依赖方向单向（下层不 import 上层）

用法：python3 docs/verify-contracts.py
退出码：0 通过，1 有失败项
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "src"

# 层号 → 允许依赖的层号（只允许依赖更小的层号）
LAYER_RULES = {
    "01": set(),
    "02": {"01"},
    "03": {"01"},
    "04": {"01"},
    "05": {"01", "lib"},
    "06": {"01"},
    "07": {"01", "02", "03", "04", "05", "06"},
}


def read(p):
    try:
        return p.read_text(encoding="utf-8", errors="ignore")
    except OSError:
        return ""


def strip_comments(text):
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    text = re.sub(r"//[^\n]*", "", text)
    return text


def check_declared_implemented():
    """K1"""
    header = strip_comments(read(SRC / "01-shared.h"))
    sources = "\n".join(strip_comments(read(f)) for f in SRC.glob("01-shared.m"))

    # 抓函数声明：返回类型 名字(
    decls = set()
    for m in re.finditer(r"^\s*(?:extern\s+)?[A-Za-z_][\w\s\*]*?\b(SB_\w+)\s*\(", header, re.M):
        decls.add(m.group(1))

    missing = []
    for name in sorted(decls):
        # 实现形式：SB_name(...) {  或  = ...
        if not re.search(rf"\b{name}\s*\([^;]*\)\s*\{{", sources):
            missing.append(name)
    return decls, missing


def check_bootstrap_calls():
    """K2"""
    boot = strip_comments(read(SRC / "07-bootstrap.m"))
    impls = set()
    for f in SRC.glob("0[2-6]-*.m"):
        for m in re.finditer(r"^\s*void\s+(SB_install\w+)\s*\(", strip_comments(read(f)), re.M):
            impls.add(m.group(1))

    missing = [n for n in sorted(impls) if n not in boot]
    return impls, missing


def check_config_used():
    """K3"""
    cfg = strip_comments(read(SRC / "00-config.h"))
    macros = set(re.findall(r"#define\s+(SB_CFG_\w+)", cfg))
    if not macros:
        return set(), sorted(macros)

    all_src = ""
    for f in SRC.rglob("*"):
        if f.suffix in (".m", ".c", ".h") and f.name != "00-config.h":
            all_src += strip_comments(read(f))

    unused = [m for m in sorted(macros) if m not in all_src]
    return macros, unused


def check_layer_direction():
    """K4"""
    problems = []
    for f in SRC.glob("*.m"):
        m = re.match(r"(\d\d)-", f.name)
        if not m:
            continue
        layer = m.group(1)
        allowed = LAYER_RULES.get(layer, set())
        text = read(f)
        for inc in re.findall(r'#import\s+"(\d\d)-', text):
            if inc != layer and inc not in allowed:
                problems.append(f"{f.name} 依赖了 {inc} 层（禁止反向或跨层）")
        for inc in re.findall(r'#import\s+"(lib)/', text):
            if inc not in allowed:
                problems.append(f"{f.name} 依赖了 lib（该层不允许）")
    return problems


def main():
    fails = []
    oks = []

    decls, missing = check_declared_implemented()
    if missing:
        fails.append(f"K1 声明但未实现: {', '.join(missing)}")
    else:
        oks.append(f"K1 {len(decls)} 个公开函数全部有实现")

    impls, missing2 = check_bootstrap_calls()
    if missing2:
        fails.append(f"K2 未被装配层调用: {', '.join(missing2)}")
    else:
        oks.append(f"K2 {len(impls)} 个安装函数全部被装配层调用")

    macros, unused = check_config_used()
    if unused:
        fails.append(f"K3 配置宏已定义但未使用: {', '.join(unused)}")
    else:
        oks.append(f"K3 {len(macros)} 个配置宏全部被使用")

    probs = check_layer_direction()
    if probs:
        fails.extend("K4 " + p for p in probs)
    else:
        oks.append("K4 依赖方向单向，无反向引用")

    print("=== 契约一致性检查 ===")
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
    sys.exit(main())
