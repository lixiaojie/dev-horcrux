#!/bin/bash
# Dev Horcrux Metrics Collector
# Collects git stats, token usage (via discover-sessions), and session summary for daily log
# Usage: collect-metrics.sh [date]
# Output: YAML-formatted metrics block + session summary table to stdout

DATE=${1:-$(date +%Y-%m-%d)}
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

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

# --- Session discovery (replaces single-JSONL parsing) ---
DISCOVER="$SCRIPT_DIR/discover-sessions.sh"
if [ -x "$DISCOVER" ]; then
    DISCOVERY_OUTPUT=$("$DISCOVER" "$DATE" 2>/dev/null)

    # Extract totals from YAML output
    SESSIONS=$(echo "$DISCOVERY_OUTPUT" | grep "^  sessions:" | head -1 | awk '{print $2}')
    MESSAGES=$(echo "$DISCOVERY_OUTPUT" | grep "^  messages:" | head -1 | awk '{print $2}')
    INPUT_T=$(echo "$DISCOVERY_OUTPUT" | grep "^    input:" | head -1 | awk '{print $2}' | tr -d ',')
    OUTPUT_T=$(echo "$DISCOVERY_OUTPUT" | grep "^    output:" | head -1 | awk '{print $2}' | tr -d ',')
    CACHE_READ=$(echo "$DISCOVERY_OUTPUT" | grep "^    cache_read:" | head -1 | awk '{print $2}' | tr -d ',')
    TOTAL_T=$(echo "$DISCOVERY_OUTPUT" | grep "^    total:" | head -1 | awk '{print $2}' | tr -d ',')
    COST=$(echo "$DISCOVERY_OUTPUT" | grep "^  estimated_cost:" | head -1 | awk '{print $2}')

    echo "sessions: ${SESSIONS:-0}"
    echo "conversation_rounds: ${MESSAGES:-0}"
    echo "tokens:"
    echo "  input: ${INPUT_T:-0}"
    echo "  output: ${OUTPUT_T:-0}"
    echo "  cache_read: ${CACHE_READ:-0}"
    echo "  total: ${TOTAL_T:-0}"
    echo "estimated_cost: ${COST:-\$0.00}"

    # --- Session summary table (markdown) ---
    echo ""
    echo "## Session Summary"
    echo "| # | Time | Msgs | Project | First Message |"
    echo "|---|------|------|---------|---------------|"

    # Parse session entries from YAML
    echo "$DISCOVERY_OUTPUT" | python3 -c "
import sys

content = sys.stdin.read()
# Extract session blocks
sessions = []
current = {}
in_sessions = False

for line in content.split('\n'):
    if line.strip() == 'sessions:':
        in_sessions = True
        continue
    if line.startswith('totals:'):
        in_sessions = False
        if current:
            sessions.append(current)
            current = {}
        break
    if not in_sessions:
        continue

    if line.startswith('  - id:'):
        if current:
            sessions.append(current)
        current = {'id': line.split(':')[1].strip()}
    elif line.startswith('    ') and ':' in line and not line.startswith('    tokens:'):
        key, _, val = line.strip().partition(':')
        current[key.strip()] = val.strip().strip('\"')

for s in sessions:
    sid = s.get('id', '?')
    start = s.get('start', '?')
    end = s.get('end', '?')
    msgs = s.get('messages', '?')
    proj = s.get('project', '?')
    msg = s.get('first_user_msg', '')[:50]
    if len(s.get('first_user_msg', '')) > 50:
        msg += '...'
    print(f'| {sid} | {start}~{end} | {msgs} | {proj} | {msg} |')
" 2>/dev/null
else
    echo "sessions: (discover-sessions.sh not found)"
    echo "conversation_rounds: (unavailable)"
    echo "tokens: (unavailable)"
fi

# --- Activity log (supplementary) ---
ACTIVITY_LOG="$HOME/.claude/session-activity.log"
if [ -f "$ACTIVITY_LOG" ]; then
    TODAY_ENTRIES=$(grep "^$DATE" "$ACTIVITY_LOG" 2>/dev/null)
    STOP_COUNT=$(echo "$TODAY_ENTRIES" | grep -c "^$DATE" 2>/dev/null)
    if [ "$STOP_COUNT" -gt 0 ]; then
        FIRST=$(echo "$TODAY_ENTRIES" | head -1 | cut -d'|' -f1 | cut -dT -f2)
        LAST=$(echo "$TODAY_ENTRIES" | tail -1 | cut -d'|' -f1 | cut -dT -f2)
        echo ""
        echo "## Activity Log"
        echo "stop_events: $STOP_COUNT"
        echo "first_active: $FIRST"
        echo "last_active: $LAST"
    fi
fi
