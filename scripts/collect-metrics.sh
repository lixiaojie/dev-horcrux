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
    echo "| # | Time | Msgs | Project | Models | Top Tools | Err | Cost | First Message |"
    echo "|---|------|------|---------|--------|-----------|-----|------|---------------|"

    # Parse session entries from YAML
    echo "$DISCOVERY_OUTPUT" | python3 -c "
import sys

content = sys.stdin.read()
lines = content.split('\n')

sessions = []
current = {}
model_tokens_block = {}
tool_calls_block = {}
in_sessions = False
in_model_tokens = False
in_tool_calls = False
current_model = None

def flush_session():
    global current, model_tokens_block, tool_calls_block, in_model_tokens, in_tool_calls, current_model
    if current:
        current['_model_tokens'] = dict(model_tokens_block)
        current['_tool_calls'] = dict(tool_calls_block)
        sessions.append(current)
    current = {}
    model_tokens_block = {}
    tool_calls_block = {}
    current_model = None
    in_model_tokens = False
    in_tool_calls = False

for line in lines:
    if line.strip() == 'sessions:':
        in_sessions = True
        continue
    if line.startswith('totals:'):
        flush_session()
        in_sessions = False
        break
    if not in_sessions:
        continue

    # New session entry
    if line.startswith('  - id:'):
        flush_session()
        current = {'id': line.split(':')[1].strip()}
        continue

    # 4-space level keys (session fields) — these reset sub-block state
    if line.startswith('    ') and not line.startswith('      '):
        key_part = line.strip()
        if key_part == 'tokens_by_model:':
            in_model_tokens = True
            in_tool_calls = False
            continue
        if key_part == 'tool_calls:':
            in_tool_calls = True
            in_model_tokens = False
            continue
        # Any other 4-space key: reset sub-block state
        in_model_tokens = False
        in_tool_calls = False
        current_model = None
        if ':' in key_part:
            key, _, val = key_part.partition(':')
            k = key.strip()
            if k not in ('tokens',):
                current[k] = val.strip().strip('\"')
        continue

    # 6-space level (model name in tokens_by_model, or tool name in tool_calls)
    if line.startswith('      ') and not line.startswith('        '):
        stripped = line.strip()
        if in_model_tokens:
            if stripped.endswith(':'):
                current_model = stripped[:-1]
                if current_model not in model_tokens_block:
                    model_tokens_block[current_model] = {}
        elif in_tool_calls and ':' in stripped:
            key, _, val = stripped.partition(':')
            try:
                tool_calls_block[key.strip()] = int(val.strip())
            except ValueError:
                pass
        continue

    # 8-space level (token fields under model)
    if line.startswith('        ') and in_model_tokens and current_model and ':' in line:
        stripped = line.strip()
        key, _, val = stripped.partition(':')
        try:
            model_tokens_block[current_model][key.strip()] = int(val.strip().replace(',', ''))
        except ValueError:
            pass

def abbrev_model(model):
    model = model.strip()
    if 'opus-4-7' in model: return 'opus-4-7'
    if 'opus-4-6' in model: return 'opus-4-6'
    if 'sonnet-4-6' in model: return 'sonnet'
    if 'sonnet-4-5' in model: return 'sonnet-4-5'
    if 'haiku' in model: return 'haiku'
    if model == '<synthetic>': return ''
    return model[:10]

def abbrev_tool(name):
    if 'chrome-devtools' in name:
        parts = name.split('__')
        return parts[-1][:12] if parts else name[:12]
    return name[:12]

for s in sessions:
    sid = s.get('id', '?')
    start = s.get('start', '?')
    end = s.get('end', '?')
    msgs = s.get('messages', '?')
    proj = s.get('project', '?')
    cost = s.get('estimated_cost', '')
    errors_raw = s.get('errors', '')
    errors = '' if not errors_raw or errors_raw == '0' else errors_raw

    # Top 2 models by token share
    mt = s.get('_model_tokens', {})
    model_totals = {}
    for m, tok in mt.items():
        if m == '<synthetic>': continue
        total = tok.get('input', 0) + tok.get('output', 0) + tok.get('cache_read', 0) + tok.get('cache_create', 0)
        if total > 0:
            model_totals[m] = total
    top_models = sorted(model_totals.items(), key=lambda x: -x[1])[:2]
    models_str = ' / '.join(abbrev_model(m) for m, _ in top_models) if top_models else '?'

    # Top 3 tools by count
    tc = s.get('_tool_calls', {})
    top3 = sorted(tc.items(), key=lambda x: -x[1])[:3]
    tools_str = ' '.join(f'{abbrev_tool(t)}({c})' for t, c in top3) if top3 else ''

    msg_text = s.get('first_user_msg', '')[:40]
    if len(s.get('first_user_msg', '')) > 40:
        msg_text += '...'

    print(f'| {sid} | {start}~{end} | {msgs} | {proj} | {models_str} | {tools_str} | {errors} | {cost} | {msg_text} |')
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
