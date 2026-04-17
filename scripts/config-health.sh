#!/bin/bash
# config-health.sh — Scan key config files for bloat and report health status
# Usage: config-health.sh [--verbose] [--project-dir DIR]
#
# Exit codes: 0 = healthy, 1 = warnings, 2 = alerts

set -euo pipefail

# ── Config ──────────────────────────────────────────────
CONF_FILE="${HOME}/.claude/dev-horcrux.conf"
[[ -f "$CONF_FILE" ]] && source "$CONF_FILE"

VERBOSE=false
PROJECT_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --verbose) VERBOSE=true; shift ;;
    --project-dir) PROJECT_DIR="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# ── Thresholds (warn, alert) ───────────────────────────
# Global index — should be pure @path references
GLOBAL_INDEX_WARN=15
GLOBAL_INDEX_ALERT=25

# Global modules (global-*.md)
GLOBAL_MODULE_WARN=80
GLOBAL_MODULE_ALERT=120

# Project CLAUDE.md
PROJECT_CLAUDE_WARN=200
PROJECT_CLAUDE_ALERT=300

# MEMORY.md (system truncates after 200 lines)
MEMORY_WARN=150
MEMORY_ALERT=200

# SKILL.md (skill-creator standard: < 500)
SKILL_WARN=400
SKILL_ALERT=500

# Inline block extraction threshold (lines)
INLINE_BLOCK_THRESHOLD=30

# ── State ──────────────────────────────────────────────
EXIT_CODE=0
WARNINGS=0
ALERTS=0
REPORT=""

# ── Helpers ────────────────────────────────────────────
check_file() {
  local file="$1" label="$2" warn="$3" alert="$4"

  if [[ ! -f "$file" ]]; then
    [[ "$VERBOSE" == true ]] && REPORT+="  SKIP  $label (not found)\n"
    return
  fi

  local lines
  lines=$(wc -l < "$file" | tr -d ' ')
  local status="OK"

  if (( lines >= alert )); then
    status="ALERT"
    (( ALERTS++ ))
    [[ $EXIT_CODE -lt 2 ]] && EXIT_CODE=2
  elif (( lines >= warn )); then
    status="WARN"
    (( WARNINGS++ ))
    [[ $EXIT_CODE -lt 1 ]] && EXIT_CODE=1
  fi

  if [[ "$status" != "OK" || "$VERBOSE" == true ]]; then
    REPORT+="  $(printf '%-5s' "$status")  $(printf '%-4s' "$lines") lines  $label\n"
  fi
}

# Count inline code/content blocks > threshold lines
check_inline_blocks() {
  local file="$1" label="$2"

  [[ ! -f "$file" ]] && return

  # Count consecutive non-empty, non-heading lines as "blocks"
  # Use awk to find code fence blocks (``` ... ```) longer than threshold
  local big_blocks
  big_blocks=$(awk -v threshold="$INLINE_BLOCK_THRESHOLD" '
    /^```/ {
      if (in_block) {
        if (block_len >= threshold) count++
        in_block = 0; block_len = 0
      } else {
        in_block = 1; block_len = 0; block_start = NR
      }
      next
    }
    in_block { block_len++ }
    END { print count+0 }
  ' "$file")

  # Also check long table blocks (consecutive | lines)
  local big_tables
  big_tables=$(awk -v threshold="$INLINE_BLOCK_THRESHOLD" '
    /^\|/ { table_len++; next }
    {
      if (table_len >= threshold) count++
      table_len = 0
    }
    END {
      if (table_len >= threshold) count++
      print count+0
    }
  ' "$file")

  local total=$(( big_blocks + big_tables ))
  if (( total > 0 )); then
    REPORT+="        ↳ $total large inline block(s) > ${INLINE_BLOCK_THRESHOLD} lines — extraction candidate\n"
    (( WARNINGS++ ))
    [[ $EXIT_CODE -lt 1 ]] && EXIT_CODE=1
  fi
}

# Check MEMORY.md specific health
check_memory() {
  local file="$1"
  [[ ! -f "$file" ]] && return

  local lines
  lines=$(wc -l < "$file" | tr -d ' ')
  local entries
  entries=$(grep -c '^\- \[' "$file" 2>/dev/null || echo 0)

  # Check for entries over 150 chars
  local long_entries
  long_entries=$(grep '^\- \[' "$file" 2>/dev/null | awk 'length > 150 { count++ } END { print count+0 }')

  if (( long_entries > 0 )); then
    REPORT+="        ↳ $long_entries MEMORY.md entries > 150 chars (should be concise index)\n"
    (( WARNINGS++ ))
    [[ $EXIT_CODE -lt 1 ]] && EXIT_CODE=1
  fi

  [[ "$VERBOSE" == true ]] && REPORT+="        ↳ $entries index entries, $lines total lines\n"
}

# ── Main Scan ──────────────────────────────────────────
REPORT+="## Config Health Report\n"
REPORT+="$(date '+%Y-%m-%d %H:%M')\n\n"

# 1. Global index
REPORT+="### Global Config (~/.claude/)\n"
check_file "${HOME}/.claude/CLAUDE.md" "CLAUDE.md (global index)" "$GLOBAL_INDEX_WARN" "$GLOBAL_INDEX_ALERT"

# 2. Global modules
for f in "${HOME}"/.claude/global-*.md; do
  [[ -f "$f" ]] || continue
  local_name=$(basename "$f")
  check_file "$f" "$local_name" "$GLOBAL_MODULE_WARN" "$GLOBAL_MODULE_ALERT"
  check_inline_blocks "$f" "$local_name"
done

check_file "${HOME}/.claude/assistant-core.md" "assistant-core.md" "$GLOBAL_MODULE_WARN" "$GLOBAL_MODULE_ALERT"

# 3. Project CLAUDE.md (scan current dir + explicit project dir)
REPORT+="\n### Project Config\n"
scan_dirs=()
_seen_real=""
if [[ -n "$PROJECT_DIR" ]]; then
  _seen_real=$(cd "$PROJECT_DIR" 2>/dev/null && pwd -P)
  scan_dirs+=("$PROJECT_DIR")
fi
if [[ -f "./CLAUDE.md" && "$(pwd)" != "$HOME/.claude" ]]; then
  real_cwd=$(pwd -P)
  if [[ "$real_cwd" != "$_seen_real" ]]; then
    scan_dirs+=("$(pwd)")
  fi
fi

for dir in "${scan_dirs[@]}"; do
  if [[ -f "$dir/CLAUDE.md" ]]; then
    check_file "$dir/CLAUDE.md" "$(basename "$dir")/CLAUDE.md" "$PROJECT_CLAUDE_WARN" "$PROJECT_CLAUDE_ALERT"
    check_inline_blocks "$dir/CLAUDE.md" "$(basename "$dir")/CLAUDE.md"
  fi
done

# 4. MEMORY.md files (search in .claude/projects/)
REPORT+="\n### Memory Files\n"
while IFS= read -r -d '' mfile; do
  rel_path="${mfile#$HOME/.claude/projects/}"
  check_file "$mfile" "MEMORY.md ($rel_path)" "$MEMORY_WARN" "$MEMORY_ALERT"
  check_memory "$mfile"
done < <(find -L "${HOME}/.claude/projects" -name "MEMORY.md" -print0 2>/dev/null)

# 5. SKILL.md files
REPORT+="\n### Skill Files\n"
while IFS= read -r -d '' sfile; do
  skill_name=$(basename "$(dirname "$sfile")")
  check_file "$sfile" "$skill_name/SKILL.md" "$SKILL_WARN" "$SKILL_ALERT"
done < <(find -L "${HOME}/.claude/skills" -maxdepth 2 -name "SKILL.md" -print0 2>/dev/null | sort -z)

# ── Summary ────────────────────────────────────────────
REPORT+="\n### Summary\n"
if (( ALERTS > 0 )); then
  REPORT+="  🔴 $ALERTS alert(s), $WARNINGS warning(s) — action needed\n"
elif (( WARNINGS > 0 )); then
  REPORT+="  🟡 $WARNINGS warning(s) — review recommended\n"
else
  REPORT+="  🟢 All config files healthy\n"
fi

echo -e "$REPORT"
exit $EXIT_CODE
