#!/usr/bin/env python3
"""lint-workflow.py — GitHub Actions 工作流静态校验

在推送前发现会让 CI 直接失败的低级错误，省一轮来回。

检查项：
  W1  YAML 语法可解析
  W2  必需字段存在（name / on / jobs）
  W3  每个 job 有 runs-on
  W4  每个 step 至少含 run 或 uses
  W5  引用的本地脚本路径真实存在
  W6  构建命令引用的源文件真实存在

用法：python3 .github/lint-workflow.py
退出码：0 通过，1 有失败项
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WF_DIR = ROOT / ".github" / "workflows"

try:
    import yaml
except ImportError:
    print("跳过：缺 PyYAML（pip install pyyaml）")
    sys.exit(0)


def check_file(path):
    fails, oks = [], []
    name = path.name

    # W1
    try:
        doc = yaml.safe_load(path.read_text(encoding="utf-8"))
    except Exception as e:
        return [f"W1 YAML 解析失败: {e}"], []
    oks.append("W1 YAML 可解析")

    if not isinstance(doc, dict):
        return ["W2 顶层不是映射"], oks

    # W2
    if "name" not in doc:
        fails.append("W2 缺 name")
    # YAML 1.1 会把裸 on 解析成布尔 True
    on_key = "on" if "on" in doc else (True if True in doc else None)
    if on_key is None:
        fails.append("W2 缺 on 触发器")
    if "jobs" not in doc or not isinstance(doc.get("jobs"), dict):
        fails.append("W2 缺 jobs")
    if not fails:
        oks.append("W2 name / on / jobs 齐全")

    jobs = doc.get("jobs") or {}
    for jname, job in jobs.items():
        if not isinstance(job, dict):
            fails.append(f"W3 job {jname} 结构异常")
            continue

        # W3
        if "runs-on" not in job:
            fails.append(f"W3 job {jname} 缺 runs-on")

        # W4
        steps = job.get("steps") or []
        if not steps:
            fails.append(f"W3 job {jname} 无 steps")
        for i, st in enumerate(steps):
            if not isinstance(st, dict):
                fails.append(f"W4 job {jname} step#{i} 结构异常")
                continue
            if "run" not in st and "uses" not in st:
                fails.append(f"W4 job {jname} step#{i} 既无 run 也无 uses")

    oks.append(f"W3/W4 {len(jobs)} 个 job 结构完整")

    text = path.read_text(encoding="utf-8")

    # W5 本地脚本引用
    refs = set(re.findall(r"python3\s+([\w./-]+\.py)", text))
    missing = [r for r in sorted(refs) if not (ROOT / r).exists()]
    if missing:
        fails.append(f"W5 引用的脚本不存在: {', '.join(missing)}")
    else:
        oks.append(f"W5 {len(refs)} 个脚本引用全部存在")

    # W6 构建源文件
    srcs = re.findall(r"([\w./-]+\.(?:m|c))\b", text)
    if srcs:
        uniq = sorted(set(srcs))
        miss = [s for s in uniq
                if not (ROOT / s).exists()
                and not (ROOT / "src" / s).exists()
                and not (ROOT / "recon" / s).exists()
                and not (ROOT / "src" / "lib" / s).exists()]
        if miss:
            fails.append(f"W6 构建源文件不存在: {', '.join(miss)}")
        else:
            oks.append(f"W6 {len(uniq)} 个构建源文件全部存在")

    return fails, oks


def main():
    if not WF_DIR.is_dir():
        print("无 .github/workflows 目录")
        return 0

    all_fails = []
    print("=== 工作流校验 ===")
    for path in sorted(WF_DIR.glob("*.y*ml")):
        fails, oks = check_file(path)
        print(f"\n[{path.name}]")
        for o in oks:
            print("  PASS " + o)
        for f in fails:
            print("  FAIL " + f)
            all_fails.append(f"{path.name}: {f}")

    print()
    if all_fails:
        print(f"结果: 失败 {len(all_fails)} 项")
        return 1
    print("结果: 全部通过")
    return 0


if __name__ == "__main__":
    sys.exit(main())
