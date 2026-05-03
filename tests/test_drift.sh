#!/usr/bin/env bash
# test_drift.sh — 4 fixture 端到端测试 doc-drift.py
#
# 每个 fixture 建临时 git repo → 跑脚本 → 断言输出
# 依赖: python3, git, jq

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DRIFT_PY="$SKILL_DIR/scripts/doc-drift.py"
TODAY=$(date +%Y-%m-%d)

pass=0
fail=0

_log_pass() { echo "  PASS  $1"; pass=$((pass + 1)); }
_log_fail() { echo "  FAIL  $1"; fail=$((fail + 1)); }

_setup_repo() {
  local dir=$1
  rm -rf "$dir"
  mkdir -p "$dir"
  (cd "$dir" && git init -q && git config user.email "t@t" && git config user.name t)
}

_commit() {
  local dir=$1 msg=$2
  (cd "$dir" && git add -A && git commit -qm "$msg")
}

# 把 init commit 的日期设成昨天，确保 --since=today 只抓"今日改动"
_commit_as_yesterday() {
  local dir=$1 msg=$2
  local yesterday
  yesterday=$(date -v-1d "+%Y-%m-%dT%H:%M:%S" 2>/dev/null \
    || date -d "yesterday" "+%Y-%m-%dT%H:%M:%S")
  (cd "$dir" && git add -A && \
    GIT_AUTHOR_DATE="$yesterday" GIT_COMMITTER_DATE="$yesterday" \
    git commit -qm "$msg")
}

_run_drift() {
  local dir=$1
  python3 "$DRIFT_PY" "$TODAY" --project-dir "$dir"
}

# ---- Fixture 1: Kit 函数改名 ----
test_fix1_kit_rename() {
  local name="fix1_kit_rename"
  local dir="/tmp/drift_test_$name"
  _setup_repo "$dir"
  mkdir -p "$dir/my-kit"
  cat > "$dir/my-kit/api.py" <<'EOF'
def get_daily():
    pass

class KlineStore:
    pass
EOF
  cat > "$dir/my-kit/CLAUDE.md" <<'EOF'
# my-kit

## API 表

- get_daily(): 获取日线
- KlineStore: 存储类
EOF
  _commit_as_yesterday "$dir" "init"
  # 改名
  sed -i.bak 's/get_daily/fetch_daily/g' "$dir/my-kit/api.py"
  rm -f "$dir/my-kit/api.py.bak"
  _commit "$dir" "rename"

  local out
  out=$(_run_drift "$dir")

  # 断言: 有候选命中 CLAUDE.md，symbols 含 get_daily
  if echo "$out" | python3 -c "
import json, sys
d = json.load(sys.stdin)
cands = d['candidates']
for c in cands:
    if 'CLAUDE.md' in c['target_doc'] and any('API' in s['heading'] for s in c['snippets']):
        matched = set()
        for s in c['snippets']:
            matched.update(s['matched_symbols'])
        if 'get_daily' in matched:
            sys.exit(0)
sys.exit(1)"; then
    _log_pass "$name: 命中 CLAUDE.md API 表 + get_daily"
  else
    _log_fail "$name: 未命中"
    echo "$out" | head -60
  fi
}

# ---- Fixture 2: Script 删除 ----
test_fix2_script_deleted() {
  local name="fix2_script_deleted"
  local dir="/tmp/drift_test_$name"
  _setup_repo "$dir"
  mkdir -p "$dir/scripts"
  cat > "$dir/scripts/old_tool.py" <<'EOF'
print("hello")
EOF
  cat > "$dir/CLAUDE.md" <<'EOF'
# Project

## 脚本清单
- `scripts/old_tool.py` 老工具
EOF
  _commit_as_yesterday "$dir" "init"
  rm "$dir/scripts/old_tool.py"
  _commit "$dir" "delete"

  local out
  out=$(_run_drift "$dir")

  if echo "$out" | python3 -c "
import json, sys
d = json.load(sys.stdin)
for c in d['candidates']:
    if 'CLAUDE.md' in c['target_doc']:
        matched = set()
        for s in c['snippets']:
            matched.update(s['matched_symbols'])
        if 'old_tool' in matched:
            sys.exit(0)
sys.exit(1)"; then
    _log_pass "$name: 删除 script 后命中 CLAUDE.md 脚本清单"
  else
    _log_fail "$name: 未命中"
    echo "$out" | head -40
  fi
}

# ---- Fixture 3: 只改 comment（不应 false positive） ----
test_fix3_comment_only() {
  local name="fix3_comment_only"
  local dir="/tmp/drift_test_$name"
  _setup_repo "$dir"
  mkdir -p "$dir/my-kit"
  cat > "$dir/my-kit/util.py" <<'EOF'
# Old comment
def helper():
    return 42
EOF
  cat > "$dir/my-kit/CLAUDE.md" <<'EOF'
# my-kit

## API 表

- helper(): 工具函数
EOF
  _commit_as_yesterday "$dir" "init"
  # 只改 comment，不碰 code
  sed -i.bak 's/Old comment/New comment, slightly different/' "$dir/my-kit/util.py"
  rm -f "$dir/my-kit/util.py.bak"
  _commit "$dir" "comment"

  local out
  out=$(_run_drift "$dir")

  # 断言: 没有命中 snippet 或候选数很少
  # comment 改动不应提取到函数 symbol，因此 CLAUDE.md 上的 helper 不应被命中
  local hits
  hits=$(echo "$out" | python3 -c "
import json, sys
d = json.load(sys.stdin)
count = 0
for c in d['candidates']:
    for s in c['snippets']:
        if 'helper' in s['matched_symbols']:
            count += 1
print(count)")

  if [[ "$hits" == "0" ]]; then
    _log_pass "$name: 只改 comment 不产生 helper 命中"
  else
    _log_fail "$name: 误命中 helper $hits 次"
    echo "$out" | head -40
  fi
}

# ---- Fixture 4: 跨项目（manifest 波及下游） ----
test_fix4_cross_project() {
  local name="fix4_cross_project"
  local dir="/tmp/drift_test_$name"
  _setup_repo "$dir"
  mkdir -p "$dir/upstream-kit" "$dir/downstream-app"
  cat > "$dir/upstream-kit/manifest.yaml" <<'EOF'
name: upstream-kit
version: 0.1.0
provides: [kline]
EOF
  cat > "$dir/upstream-kit/CLAUDE.md" <<'EOF'
# upstream-kit
对外接口 provides: kline
EOF
  cat > "$dir/downstream-app/CLAUDE.md" <<'EOF'
# downstream-app
依赖 upstream-kit 的 kline 接口
EOF
  _commit_as_yesterday "$dir" "init"
  # 改 manifest
  sed -i.bak 's/kline/kline_v2/' "$dir/upstream-kit/manifest.yaml"
  rm -f "$dir/upstream-kit/manifest.yaml.bak"
  _commit "$dir" "update"

  local out
  out=$(_run_drift "$dir")

  # 断言: 候选包含 upstream-kit/CLAUDE.md（manifest 规则命中）
  if echo "$out" | python3 -c "
import json, sys
d = json.load(sys.stdin)
for c in d['candidates']:
    if c.get('rule_pattern') == '*/manifest.yaml' and 'upstream-kit/CLAUDE.md' in c['target_doc']:
        sys.exit(0)
sys.exit(1)"; then
    _log_pass "$name: manifest 变更命中 upstream CLAUDE.md"
  else
    _log_fail "$name: 未命中"
    echo "$out" | head -40
  fi
}

# ---- 运行所有 ----
test_fix1_kit_rename
test_fix2_script_deleted
test_fix3_comment_only
test_fix4_cross_project

echo ""
echo "=== Results: $pass passed, $fail failed ==="
exit $((fail > 0 ? 1 : 0))
