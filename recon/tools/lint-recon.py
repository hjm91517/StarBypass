#!/usr/bin/env python3
"""lint-recon.py — 侦察版源码静态检查

抓的是那些「编译能过、运行时静默失效或崩溃」的问题：

  L1  @selector(X) 引用的方法在本项目里是否真的定义
  L2  所有 RCOrigIMP(...) 的返回值是否做了非空判断
  L3  imp_implementationWithBlock 的块里是否调用了原实现（否则原逻辑丢失）
  L4  NSTimer 的 selector 是否存在于目标类
  L5  是否存在静态 dispatch_ / _dyld_ 引用（会崩在 dyld 加载期）
  L6  导出的 RCInstall* 是否都有定义且被装配层调用

用法：python3 recon/tools/lint-recon.py
退出码：0 通过，1 有失败项
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT

FILES = sorted(SRC.glob("*.m")) + sorted(SRC.glob("*.c"))


def read(p):
    return p.read_text(encoding="utf-8", errors="ignore")


def strip_comments(t):
    t = re.sub(r"/\*.*?\*/", "", t, flags=re.S)
    t = re.sub(r"//[^\n]*", "", t)
    return t


def collect(all_text):
    """收集定义的方法名与选择器"""
    # - (ret)name  /  + (ret)name
    defined = set()
    for m in re.finditer(r"^[-+]\s*\([^)]*\)\s*(\w+)", all_text, re.M):
        defined.add(m.group(1))
    # 带参数的方法名 —— 从实现体里带冒号的签名不好抓，改用选择器完整形式
    for m in re.finditer(r"^[-+]\s*\([^)]*\)\s*([\w:]+)", all_text, re.M):
        defined.add(m.group(1))
    # 协议/系统方法声明（如 setText:、presentViewController:animated:completion:）
    for m in re.finditer(r"^[-+]\s*\([^)]*\)\s*(set\w+:[\w:]*)", all_text, re.M):
        defined.add(m.group(1))
    return defined


def l1_selectors(all_text, defined):
    """@selector(X) 引用的方法是否定义过（或来自系统框架）"""
    problems = []
    system_prefixes = (
        "set", "init", "present", "dismiss", "add", "remove", "insert",
        "reload", "layout", "draw", "did", "will", "should", "can",
        "numberOf", "tableView", "collectionView", "textField", "scrollView",
    )
    for m in re.finditer(r"@selector\(\s*([\w:]+)\s*\)", all_text):
        sel = m.group(1)
        if sel in defined:
            continue
        if sel.startswith(system_prefixes):
            continue
        # 只检查无参选择器（our own callbacks 通常无参或单参）
        if ":" not in sel:
            problems.append(f"L1 @selector({sel}) 在本项目内无定义")
    return problems


def _func_start(t, pos):
    """向上找当前函数定义起点。

    只认列首（无缩进）的函数定义：
      - C 函数：  static id RC_foo(...)   /  void RC_bar(void)
      - ObjC 方法：- (void)foo {
    这样不会把函数内的块字面量或局部 static 误判成函数头。
    """
    pat_c = re.compile(r"^[A-Za-z_][A-Za-z0-9_ \t\*]*\s\**\w+\s*\(", re.M)
    pat_m = re.compile(r"^[-+]\s*\(", re.M)

    best = 0
    for pat in (pat_c, pat_m):
        for m in pat.finditer(t, 0, pos):
            # 排除缩进行（^ 在 MULTILINE 下也会命中行首，需检查前一个字符）
            if m.start() > 0 and t[m.start() - 1] not in "\n":
                continue
            if m.start() < pos:
                best = max(best, m.start())
    return best


def l2_origimp_checks(files):
    """RCOrigIMP 取到的指针，每次调用前必须在该函数内有判空守卫"""
    problems = []
    for f in files:
        t = strip_comments(read(f))
        vars_ = set(re.findall(r"(\w+)\s*=\s*\([^;]*?\)\s*RCOrigIMP\(", t))
        for var in vars_:
            for m in re.finditer(rf"\b{var}\s*\(", t):
                line_start = t.rfind("\n", 0, m.start()) + 1
                line_end = t.find("\n", m.start())
                line_txt = t[line_start:line_end if line_end > 0 else len(t)]
                if "RCOrigIMP" in line_txt:
                    continue

                fs = _func_start(t, m.start())
                scope = t[fs:m.start()]
                guarded = (
                    re.search(rf"if\s*\(\s*!\s*{var}\s*\)", scope) or
                    re.search(rf"if\s*\(\s*{var}\s*\)", scope) or
                    re.search(rf"{var}\s*\?", scope)
                )
                if not guarded:
                    line = t[:m.start()].count("\n") + 1
                    problems.append(
                        f"L2 {f.name}:{line} 调用 {var}(...) 前未判空")
    return problems


def l3_block_calls_orig(files):
    """imp_implementationWithBlock 内是否调用了 orig"""
    problems = []
    for f in files:
        t = strip_comments(read(f))
        idx = 0
        while True:
            i = t.find("imp_implementationWithBlock(", idx)
            if i < 0:
                break
            # 取该调用的括号范围
            depth = 0
            j = i + len("imp_implementationWithBlock")
            start = t.find("(", j)
            for k in range(start, len(t)):
                if t[k] == "(":
                    depth += 1
                elif t[k] == ")":
                    depth -= 1
                    if depth == 0:
                        body = t[start:k + 1]
                        break
            else:
                break
            if "orig" in body and "(" not in body.replace("(", "", 0):
                pass
            # 块里必须出现对 orig 的调用
            if "orig" not in body:
                line = t[:i].count("\n") + 1
                problems.append(
                    f"L3 {f.name}:{line} 包装块未调用 orig，原逻辑会丢失")
            idx = k
    return problems


def l4_timer_selectors(all_text):
    """NSTimer 的 selector 是否为已定义方法"""
    problems = []
    for m in re.finditer(
            r"scheduledTimerWithTimeInterval:[^;]*?selector:\s*@selector\((\w+)\)",
            all_text, re.S):
        sel = m.group(1)
        if not re.search(rf"^-\s*\([^)]*\)\s*{sel}\b", all_text, re.M):
            problems.append(f"L4 NSTimer 的 selector {sel}() 未定义，定时器会崩")
    return problems


def l5_no_static_dispatch(files):
    """不得出现静态 dispatch_ / _dyld_ 引用"""
    problems = []
    for f in files:
        t = strip_comments(read(f))
        for pat in (r"\bdispatch_\w+\s*\(", r"\b_dyld_\w+\s*\("):
            for m in re.finditer(pat, t):
                line = t[:m.start()].count("\n") + 1
                # 允许出现在字符串里（dlsym 名字）
                ctx = t[max(0, m.start() - 1):m.start()]
                if ctx.strip().endswith('"'):
                    continue
                problems.append(
                    f"L5 {f.name}:{line} 静态引用 {m.group(0).strip()}，应走 dlsym")
    return problems


def l6_export_defined(all_text, files):
    """RCInstall* 是否都有定义并被装配层调用"""
    problems = []
    exports = set(re.findall(r"^void\s+(RCInstall\w+)\s*\(", all_text, re.M))
    boot = strip_comments(read(SRC / "07-bootstrap.m"))
    for name in sorted(exports):
        if name not in boot:
            problems.append(f"L6 {name} 未被装配层调用")
    return problems, exports


def main():
    if not FILES:
        print("未找到源码")
        return 1

    all_text = "\n".join(strip_comments(read(f)) for f in FILES)
    defined = collect(all_text)

    fails = []
    oks = []

    p1 = l1_selectors(all_text, defined)
    if p1:
        fails += p1
    else:
        oks.append("L1 @selector 引用全部有定义")

    p2 = l2_origimp_checks(FILES)
    if p2:
        fails += p2
    else:
        oks.append("L2 原实现指针均做了判空")

    p3 = l3_block_calls_orig(FILES)
    if p3:
        fails += p3
    else:
        oks.append("L3 所有包装块都调用了原实现")

    p4 = l4_timer_selectors(all_text)
    if p4:
        fails += p4
    else:
        oks.append("L4 定时器 selector 全部存在")

    p5 = l5_no_static_dispatch(FILES)
    if p5:
        fails += p5
    else:
        oks.append("L5 无静态 dispatch_/_dyld_ 引用")

    p6, exports = l6_export_defined(all_text, FILES)
    if p6:
        fails += p6
    else:
        oks.append(f"L6 {len(exports)} 个安装函数全部被装配层调用")

    print("=== 侦察版源码检查 ===")
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
