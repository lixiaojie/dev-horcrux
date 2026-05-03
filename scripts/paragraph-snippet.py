#!/usr/bin/env python3
"""paragraph-snippet — 按 markdown heading 切段 + 提取命中 symbol 的段落。

用法:
    paragraph-snippet.py <markdown_file> <symbol1> [symbol2 ...]
    paragraph-snippet.py <markdown_file> --symbols-file <file>

输出: JSON 数组，每项是命中的段落：
    [{"heading": "## API", "line": 42, "content": "...", "matched_symbols": ["bar"]}]

依赖: 纯 stdlib（re / json / pathlib / argparse）。
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

HEADING_RE = re.compile(r"^(#{1,6})\s+(.+?)\s*$")
FENCE_RE = re.compile(r"^(```|~~~)")
CONTEXT_LINES = 10  # symbol 前后上下文行数上限


def split_by_heading(lines: list[str]) -> list[dict]:
    """按 heading 切段，不破坏代码块。

    返回: [{"heading": str, "start": int (1-based), "end": int, "body": list[str]}]
    """
    sections: list[dict] = []
    current = {"heading": "(preamble)", "level": 0, "start": 1, "body": []}
    in_fence = False

    for idx, line in enumerate(lines, start=1):
        if FENCE_RE.match(line):
            in_fence = not in_fence
            current["body"].append(line)
            continue

        if not in_fence:
            m = HEADING_RE.match(line)
            if m:
                current["end"] = idx - 1
                if current["body"]:
                    sections.append(current)
                current = {
                    "heading": m.group(0).rstrip(),
                    "level": len(m.group(1)),
                    "start": idx,
                    "body": [line],
                }
                continue

        current["body"].append(line)

    current["end"] = len(lines)
    if current["body"]:
        sections.append(current)

    return sections


def find_hits(sections: list[dict], symbols: list[str]) -> list[dict]:
    """对每个 section 找 symbol 命中，返回命中段落列表（含上下文截取）。"""
    hits: list[dict] = []
    escaped = [re.escape(s) for s in symbols]
    if not escaped:
        return hits
    # word boundary 匹配避免 `bar` 命中 `barometer`
    pattern = re.compile(r"\b(" + "|".join(escaped) + r")\b")

    for sec in sections:
        matched: set[str] = set()
        hit_lines: list[int] = []
        for i, line in enumerate(sec["body"]):
            for m in pattern.finditer(line):
                matched.add(m.group(1))
                hit_lines.append(i)

        if not matched:
            continue

        # 截取 ± CONTEXT_LINES
        body = sec["body"]
        if len(body) <= 2 * CONTEXT_LINES + 1:
            content = "".join(body)
        else:
            first = max(0, min(hit_lines) - CONTEXT_LINES)
            last = min(len(body), max(hit_lines) + CONTEXT_LINES + 1)
            content = "".join(body[first:last])
            if first > 0:
                content = "... (truncated)\n" + content
            if last < len(body):
                content = content + "... (truncated)\n"

        hits.append(
            {
                "heading": sec["heading"],
                "line": sec["start"],
                "content": content.rstrip(),
                "matched_symbols": sorted(matched),
            }
        )

    return hits


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("markdown_file", type=Path)
    parser.add_argument("symbols", nargs="*")
    parser.add_argument("--symbols-file", type=Path)
    args = parser.parse_args()

    path: Path = args.markdown_file
    if not path.exists():
        print(json.dumps({"error": f"file not found: {path}"}))
        return 1

    symbols = list(args.symbols)
    if args.symbols_file and args.symbols_file.exists():
        symbols.extend(
            s.strip()
            for s in args.symbols_file.read_text(encoding="utf-8").splitlines()
            if s.strip()
        )

    symbols = [s for s in symbols if s]
    if not symbols:
        print("[]")
        return 0

    try:
        lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
    except UnicodeDecodeError:
        print(json.dumps({"error": f"not utf-8: {path}"}))
        return 1

    sections = split_by_heading(lines)
    hits = find_hits(sections, symbols)
    print(json.dumps(hits, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
