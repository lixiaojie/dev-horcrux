#!/bin/bash
# Dev Journal Metrics Collector
# Collects git stats and token usage for the daily log
# Usage: collect-metrics.sh [date] [session-jsonl-path]
# Output: YAML-formatted metrics block to stdout

DATE=${1:-$(date +%Y-%m-%d)}
SESSION_JSONL="$2"

echo "## Metrics"

# --- Git stats (today's commits) ---
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    COMMITS=$(git log --oneline --since="$DATE 00:00" --until="$DATE 23:59" 2>/dev/null | wc -l | tr -d ' ')
    if [ "$COMMITS" -gt 0 ]; then
        STAT=$(git log --since="$DATE 00:00" --until="$DATE 23:59" --stat --format="" 2>/dev/null | tail -1)
        FILES=$(echo "$STAT" | grep -oE '[0-9]+ file' | grep -oE '[0-9]+')
        INSERTIONS=$(echo "$STAT" | grep -oE '[0-9]+ insertion' | grep -oE '[0-9]+')
        DELETIONS=$(echo "$STAT" | grep -oE '[0-9]+ deletion' | grep -oE '[0-9]+')
        echo "code_changes:"
        echo "  files_modified: ${FILES:-0}"
        echo "  lines_added: ${INSERTIONS:-0}"
        echo "  lines_removed: ${DELETIONS:-0}"
        echo "  commits: $COMMITS"
    else
        echo "code_changes: none"
    fi
else
    echo "code_changes: not a git repo"
fi

# --- Token usage (from session JSONL) ---
if [ -n "$SESSION_JSONL" ] && [ -f "$SESSION_JSONL" ]; then
    ANALYSIS=$(python3 - "$SESSION_JSONL" << 'PYEOF'
import json, sys
from pathlib import Path

fp = Path(sys.argv[1])
input_t = output_t = cache_create = cache_read = messages = 0

with open(fp) as f:
    for line in f:
        try:
            data = json.loads(line)
            if data.get('type') == 'assistant' and 'message' in data:
                messages += 1
                u = data['message'].get('usage', {})
                input_t += u.get('input_tokens', 0)
                output_t += u.get('output_tokens', 0)
                cache_create += u.get('cache_creation_input_tokens', 0)
                cache_read += u.get('cache_read_input_tokens', 0)
        except Exception:
            pass

total_input = input_t + cache_create + cache_read
total = total_input + output_t
cost = total_input * 3 / 1_000_000 + output_t * 15 / 1_000_000

print(f"conversation_rounds: {messages}")
print(f"tokens:")
print(f"  input: {input_t:,}")
print(f"  output: {output_t:,}")
print(f"  cache_read: {cache_read:,}")
print(f"  total: {total:,}")
print(f"estimated_cost: ${cost:.2f}")
PYEOF
    )
    echo "$ANALYSIS"
else
    echo "conversation_rounds: (run /cost for details)"
    echo "tokens: (session JSONL not provided)"
fi

# --- Activity log (session count + time range) ---
ACTIVITY_LOG="$HOME/.claude/session-activity.log"
if [ -f "$ACTIVITY_LOG" ]; then
    TODAY_ENTRIES=$(grep "^$DATE" "$ACTIVITY_LOG" 2>/dev/null)
    SESSION_COUNT=$(echo "$TODAY_ENTRIES" | grep -c "^$DATE" 2>/dev/null)
    if [ "$SESSION_COUNT" -gt 0 ]; then
        FIRST=$(echo "$TODAY_ENTRIES" | head -1 | cut -d'|' -f1 | cut -dT -f2)
        LAST=$(echo "$TODAY_ENTRIES" | tail -1 | cut -d'|' -f1 | cut -dT -f2)
        echo "activity:"
        echo "  stop_events: $SESSION_COUNT"
        echo "  first_active: $FIRST"
        echo "  last_active: $LAST"
    fi
fi
