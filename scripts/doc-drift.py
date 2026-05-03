#!/usr/bin/env python3
"""doc-drift — 检测当日 git diff 可能波及的文档，输出候选 JSON 供 Claude 做语义对比。

用法:
    doc-drift.py <date> [--project-dir DIR] [--output FILE] [--rules FILE]

输出: candidates.json (stdout 或 --output 指定路径)
    {
      "date": "2026-05-03",
      "project_dir": "/path",
      "diff_summary": {"files": N, "insertions": N, "deletions": N, "oversize": bool},
      "candidates": [
        {
          "id": 1,
          "rule_pattern": "*-kit/**/*.py",
          "severity": "medium",
          "changed_file": "path",
          "changed_symbols": ["foo", "bar"],
          "target_doc": "path/to/CLAUDE.md",
          "check_hints": ["..."],
          "snippets": [...]
        }
      ],
      "truncated": bool
    }

依赖: 纯 stdlib（subprocess / fnmatch / pathlib / json / re）。
yaml 用简易解析（不引入 PyYAML，保持零依赖）。
"""
from __future__ import annotations

import argparse
import fnmatch
import json
import re
import subprocess
import sys
from functools import lru_cache
from pathlib import Path
from typing import Any

# 跳过 symbol 提取的文件扩展名（非代码）
NON_CODE_EXTS = {".yaml", ".yml", ".json", ".toml", ".ini", ".md", ".txt"}

# ---- 限制 ----
MAX_CANDIDATES = 10
MAX_DIFF_LINES = 1500  # 2026-05-03: 500→1500（真实一天 SAK 6681 行触发过度保护）
MAX_JSON_BYTES = 100 * 1024
TARGET_DOC_NAMES = ("CLAUDE.md", "README.md", "MEMORY.md")

# ---- YAML 简易解析（只处理 drift-rules.yaml 的子集） ----
# 支持: key: value / key: | `- item` / 嵌套 dict in list
# 原因: 不想引 PyYAML，保持脚本零依赖


def parse_rules_yaml(text: str) -> list[dict]:
    """解析 drift-rules.yaml，只认识 rules 列表下的固定字段。"""
    lines = text.splitlines()
    rules: list[dict] = []
    current: dict[str, Any] | None = None
    current_list_key: str | None = None

    for raw in lines:
        # 去注释
        line = re.sub(r"\s+#.*$", "", raw).rstrip()
        if not line or line.lstrip().startswith("#"):
            continue

        if line.rstrip() == "rules:":
            continue

        # 规则条目起始: `  - pattern: "xxx"`
        m = re.match(r"^\s{2}-\s+(\w+):\s*(.*)$", line)
        if m:
            if current is not None:
                rules.append(current)
            current = {}
            key, val = m.group(1), m.group(2).strip()
            current[key] = _unquote(val) if val else []
            current_list_key = key if not val else None
            continue

        # 字段续行: `    pattern: "xxx"`
        m = re.match(r"^\s{4}(\w+):\s*(.*)$", line)
        if m and current is not None:
            key, val = m.group(1), m.group(2).strip()
            if val:
                current[key] = _unquote(val)
                current_list_key = None
            else:
                current[key] = []
                current_list_key = key
            continue

        # 列表项: `      - "xxx"`
        m = re.match(r"^\s{6}-\s+(.*)$", line)
        if m and current is not None and current_list_key is not None:
            current[current_list_key].append(_unquote(m.group(1).strip()))
            continue

    if current is not None:
        rules.append(current)

    return rules


def _unquote(s: str) -> str:
    s = s.strip()
    if len(s) >= 2 and s[0] == s[-1] and s[0] in ("'", '"'):
        return s[1:-1]
    return s


# ---- git diff 获取 ----


def get_diff(project_dir: Path, date: str) -> tuple[list[tuple[str, str]], dict]:
    """返回 [(status, path)] 列表 + summary dict。

    status: M/A/D/R100/... (git 原样)
    """
    # 使用 git log 找当日所有 commit 的 name-status
    try:
        log_out = subprocess.run(
            [
                "git",
                "-C",
                str(project_dir),
                "log",
                "--all",
                "--no-merges",
                f"--since={date} 00:00",
                f"--until={date} 23:59:59",
                "--name-status",
                "--pretty=format:",
            ],
            capture_output=True,
            text=True,
            check=True,
        )
    except subprocess.CalledProcessError as e:
        return [], {"error": f"git log failed: {e.stderr}", "files": 0}

    files: list[tuple[str, str]] = []
    seen: set[str] = set()
    for line in log_out.stdout.splitlines():
        line = line.strip()
        if not line:
            continue
        parts = line.split("\t")
        if len(parts) < 2:
            continue
        status, path = parts[0], parts[-1]
        if path in seen:
            continue
        seen.add(path)
        files.append((status, path))

    # 获取 insertions/deletions 总量
    try:
        stat_out = subprocess.run(
            [
                "git",
                "-C",
                str(project_dir),
                "log",
                "--all",
                "--no-merges",
                f"--since={date} 00:00",
                f"--until={date} 23:59:59",
                "--shortstat",
                "--pretty=format:",
            ],
            capture_output=True,
            text=True,
            check=True,
        )
        insertions = sum(
            int(m.group(1))
            for m in re.finditer(r"(\d+) insertion", stat_out.stdout)
        )
        deletions = sum(
            int(m.group(1))
            for m in re.finditer(r"(\d+) deletion", stat_out.stdout)
        )
    except subprocess.CalledProcessError:
        insertions = deletions = 0

    summary = {
        "files": len(files),
        "insertions": insertions,
        "deletions": deletions,
        "oversize": (insertions + deletions) > MAX_DIFF_LINES,
    }
    return files, summary


def get_file_diff_symbols(
    project_dir: Path, date: str, path: str
) -> list[str]:
    """从当日 diff 里提取被改动的 symbol（函数名/类名/文件名）。

    非代码文件（yaml/json/md 等）只取文件名本身，不扫 diff 内容，避免把配置 key 当 symbol。
    """
    symbols: set[str] = set()
    # 文件名本身（不含扩展名）
    stem = Path(path).stem
    if stem and len(stem) > 2:
        symbols.add(stem)

    ext = Path(path).suffix.lower()
    if ext in NON_CODE_EXTS:
        return sorted(symbols)

    try:
        diff_out = subprocess.run(
            [
                "git",
                "-C",
                str(project_dir),
                "log",
                "--all",
                "--no-merges",
                f"--since={date} 00:00",
                f"--until={date} 23:59:59",
                "-p",
                "--pretty=format:",
                "--",
                path,
            ],
            capture_output=True,
            text=True,
            check=True,
        )
    except subprocess.CalledProcessError:
        return sorted(symbols)

    patterns = [
        re.compile(r"^[+-]\s*def\s+([a-zA-Z_][a-zA-Z0-9_]*)"),
        re.compile(r"^[+-]\s*class\s+([a-zA-Z_][a-zA-Z0-9_]*)"),
        re.compile(r"^[+-]\s*([a-zA-Z_][a-zA-Z0-9_]{3,})\s*[:=]"),
    ]
    for line in diff_out.stdout.splitlines():
        if not (line.startswith("+") or line.startswith("-")):
            continue
        if line.startswith(("+++", "---")):
            continue
        for p in patterns:
            m = p.match(line)
            if m:
                sym = m.group(1)
                if not sym.startswith("_") and len(sym) > 2:
                    symbols.add(sym)

    return sorted(symbols)


# ---- 匹配 + 候选产出 ----


@lru_cache(maxsize=256)
def _glob_to_regex(pattern: str) -> re.Pattern:
    """glob → regex。shell 风格（单 `*` 不跨 `/`，`**` 跨层）。

    自己写 translator，不用 fnmatch（fnmatch 的 `*` 匹配 `/`，语义不符）。
    """
    out: list[str] = ["(?s:"]
    i = 0
    n = len(pattern)
    while i < n:
        c = pattern[i]
        if c == "*":
            # 连续的 `**`
            if i + 1 < n and pattern[i + 1] == "*":
                # `/**/` → 可选目录层  `**/` → 可选目录层  `/**` → 任意后缀 `**` → 任意
                if i + 2 < n and pattern[i + 2] == "/":
                    # `**/` → (?:.*/)?
                    if i > 0 and pattern[i - 1] == "/":
                        # 前面已经有 `/`，这里产出 `(?:.*/)?` 并跳过 `**/`
                        out.append("(?:.*/)?")
                    else:
                        out.append("(?:.*/)?")
                    i += 3
                    continue
                # 尾部 `**`
                out.append(".*")
                i += 2
                continue
            # 单个 `*`：不跨 `/`
            out.append("[^/]*")
            i += 1
            continue
        if c == "?":
            out.append("[^/]")
            i += 1
            continue
        if c in ".^$+{}[]|()\\":
            out.append(re.escape(c))
            i += 1
            continue
        out.append(c)
        i += 1
    out.append(r")\Z")
    return re.compile("".join(out))


def _match_glob(path: str, pattern: str) -> bool:
    return bool(_glob_to_regex(pattern).match(path))


def match_rules(changed_path: str, rules: list[dict]) -> list[dict]:
    matched: list[dict] = []
    for rule in rules:
        pattern = rule.get("pattern", "")
        if _match_glob(changed_path, pattern):
            matched.append(rule)
    return matched


def find_target_docs(project_dir: Path, changed_path: str) -> list[Path]:
    """在变更文件的各级父目录下找 CLAUDE.md / README.md / MEMORY.md。"""
    docs: list[Path] = []
    p = project_dir / changed_path
    for parent in [p.parent] + list(p.parents):
        if not str(parent).startswith(str(project_dir.parent)):
            break
        for name in TARGET_DOC_NAMES:
            candidate = parent / name
            try:
                if candidate.exists() and candidate.is_file():
                    if candidate not in docs:
                        docs.append(candidate)
            except PermissionError:
                pass
        if parent == project_dir.parent:
            break
    return docs


def run_snippet(
    doc_path: Path, symbols: list[str], script_dir: Path
) -> list[dict]:
    """调用 paragraph-snippet.py 提取命中段落。"""
    if not symbols:
        return []
    try:
        result = subprocess.run(
            [
                sys.executable,
                str(script_dir / "paragraph-snippet.py"),
                str(doc_path),
                *symbols,
            ],
            capture_output=True,
            text=True,
            timeout=10,
        )
        if result.returncode != 0:
            return []
        return json.loads(result.stdout or "[]")
    except (subprocess.TimeoutExpired, json.JSONDecodeError, PermissionError):
        return []


# ---- 主流程 ----


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("date", help="YYYY-MM-DD")
    parser.add_argument("--project-dir", type=Path, default=Path.cwd())
    parser.add_argument("--output", type=Path, default=None)
    parser.add_argument("--rules", type=Path, default=None)
    args = parser.parse_args()

    script_dir = Path(__file__).resolve().parent
    rules_path = args.rules or (script_dir / "drift-rules.yaml")
    if not rules_path.exists():
        print(
            json.dumps({"error": f"rules file not found: {rules_path}"}),
            file=sys.stderr,
        )
        return 1

    rules = parse_rules_yaml(rules_path.read_text(encoding="utf-8"))
    project_dir = args.project_dir.resolve()

    files, summary = get_diff(project_dir, args.date)

    candidates: list[dict] = []
    cid = 0
    oversize = summary.get("oversize", False)
    for status, path in files:
        matched = match_rules(path, rules)
        if not matched:
            continue
        # oversize 时跳过 symbol 提取（diff 太大读 -p 成本高），仍产出候选，让 Claude 知道改了哪些文件
        symbols = [] if oversize else get_file_diff_symbols(project_dir, args.date, path)
        # 即使 oversize 也保留文件 stem 作为 symbol（用于命中 CLAUDE.md 里的文件引用）
        if oversize:
            stem = Path(path).stem
            if stem and len(stem) > 2:
                symbols = [stem]
        target_docs = find_target_docs(project_dir, path)

        for rule in matched:
            for doc in target_docs:
                cid += 1
                snippets = run_snippet(doc, symbols, script_dir)
                candidates.append(
                    {
                        "id": cid,
                        "rule_pattern": rule.get("pattern"),
                        "severity": rule.get("severity", "medium"),
                        "changed_file": path,
                        "status": status,
                        "changed_symbols": symbols[:20],  # 限 20
                        "target_doc": str(doc.relative_to(project_dir))
                        if doc.is_relative_to(project_dir)
                        else str(doc),
                        "check_hints": rule.get("check_hints", []),
                        "snippets": snippets,
                    }
                )
                if len(candidates) >= MAX_CANDIDATES * 3:
                    break
            if len(candidates) >= MAX_CANDIDATES * 3:
                break
        if len(candidates) >= MAX_CANDIDATES * 3:
            break

    # 按 severity 排序，截 top N
    sev_order = {"high": 0, "medium": 1, "low": 2}
    candidates.sort(key=lambda c: (sev_order.get(c["severity"], 99), c["id"]))
    total_before_trunc = len(candidates)
    truncated = total_before_trunc > MAX_CANDIDATES
    candidates = candidates[:MAX_CANDIDATES]

    out = {
        "date": args.date,
        "project_dir": str(project_dir),
        "diff_summary": summary,
        "candidates": candidates,
        "total_candidates": total_before_trunc,
        "truncated": truncated,
    }

    body = json.dumps(out, ensure_ascii=False, indent=2)
    if len(body.encode("utf-8")) > MAX_JSON_BYTES:
        # 压掉 snippets 的详细内容
        for c in candidates:
            for s in c.get("snippets", []):
                if "content" in s and len(s["content"]) > 200:
                    s["content"] = s["content"][:200] + "... (truncated)"
        out["truncated"] = True
        body = json.dumps(out, ensure_ascii=False, indent=2)

    if args.output:
        args.output.write_text(body, encoding="utf-8")
    else:
        print(body)
    return 0


if __name__ == "__main__":
    sys.exit(main())
