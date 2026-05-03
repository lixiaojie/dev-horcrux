#!/bin/bash
# Dev Horcrux Session Discovery
# Scans all JSONL session files and outputs structured session data for a given date
# Usage: discover-sessions.sh YYYY-MM-DD [timezone-offset] [--min-msgs=N]
# Output: YAML-formatted session list to stdout
# Cost uses Anthropic public list prices. Real billing may differ (Bedrock, Vertex, enterprise).

DATE=${1:-$(date +%Y-%m-%d)}
TZ_OFFSET=${2:-8}
MIN_MSGS=5

# Parse optional flags
for arg in "$@"; do
    case "$arg" in
        --min-msgs=*) MIN_MSGS="${arg#*=}" ;;
    esac
done

# Read TZ_OFFSET from config if not explicitly passed
if [ "$#" -lt 2 ]; then
    CONF="$HOME/.claude/dev-horcrux.conf"
    if [ -f "$CONF" ]; then
        # shellcheck source=/dev/null
        source "$CONF"
        [ -n "$TZ_OFFSET_CONF" ] && TZ_OFFSET="$TZ_OFFSET_CONF"
    fi
fi

python3 - "$DATE" "$TZ_OFFSET" "$MIN_MSGS" << 'PYEOF'
import json
import sys
from pathlib import Path
from datetime import datetime, timedelta, timezone
from collections import defaultdict

target_date = sys.argv[1]
tz_offset = int(sys.argv[2])
min_msgs = int(sys.argv[3])

LOCAL_TZ = timezone(timedelta(hours=tz_offset))
target_start = datetime.strptime(target_date, '%Y-%m-%d').replace(tzinfo=LOCAL_TZ)
target_end = target_start + timedelta(days=1)

# --- Per-model pricing (Anthropic public list, per 1M tokens) ---
PRICING = {
    'claude-opus-4-7':   {'input': 15,  'output': 75,  'cache_read': 1.5,  'cache_create': 18.75},
    'claude-opus-4-6':   {'input': 15,  'output': 75,  'cache_read': 1.5,  'cache_create': 18.75},
    'claude-sonnet-4-6': {'input':  3,  'output': 15,  'cache_read': 0.3,  'cache_create':  3.75},
    'claude-sonnet-4-5': {'input':  3,  'output': 15,  'cache_read': 0.3,  'cache_create':  3.75},
    'claude-haiku-4-5':  {'input':  1,  'output':  5,  'cache_read': 0.1,  'cache_create':  1.25},
}
FALLBACK = PRICING['claude-sonnet-4-6']

def price_entry(model):
    if not model:
        return FALLBACK
    for key, rate in PRICING.items():
        if model.startswith(key):
            return rate
    return FALLBACK

projects_dir = Path.home() / '.claude' / 'projects'
if not projects_dir.exists():
    print(f"date: {target_date}")
    print(f"timezone: UTC+{tz_offset}")
    print("sessions: []")
    print("totals:")
    print("  sessions: 0")
    sys.exit(0)

sessions = []

for proj_dir in projects_dir.iterdir():
    if not proj_dir.is_dir():
        continue
    proj_name = proj_dir.name

    for jsonl in proj_dir.glob('[0-9a-f]*.jsonl'):
        first_ts = last_ts = None
        cwd = ''
        msg_count = 0
        input_t = output_t = cache_create = cache_read = 0
        first_user_msg = ''
        session_id = jsonl.stem
        error_count = 0

        # Per-model token accumulators
        model_tokens = defaultdict(lambda: {'input': 0, 'output': 0, 'cache_read': 0, 'cache_create': 0})
        # Tool call counts
        tool_calls = defaultdict(int)

        try:
            with open(jsonl, errors='replace') as f:
                for line in f:
                    try:
                        data = json.loads(line)
                    except (json.JSONDecodeError, ValueError):
                        continue

                    ts_str = data.get('timestamp', '')
                    if ts_str:
                        try:
                            ts = datetime.fromisoformat(ts_str.replace('Z', '+00:00'))
                            if ts.tzinfo is None:
                                ts = ts.replace(tzinfo=timezone.utc)
                            local_ts = ts.astimezone(LOCAL_TZ)

                            if first_ts is None:
                                first_ts = local_ts
                            last_ts = local_ts
                        except (ValueError, OverflowError):
                            pass

                    if data.get('type') == 'system' and 'cwd' in data:
                        cwd = data['cwd']

                    # Error tracking
                    if data.get('isError') is True:
                        error_count += 1
                    msg_obj = data.get('message', {})
                    if isinstance(msg_obj, dict) and msg_obj.get('isError') is True:
                        error_count += 1

                    if data.get('type') == 'assistant' and 'message' in data:
                        msg_count += 1
                        u = data['message'].get('usage', {})
                        model = data['message'].get('model', '')

                        i_tok = u.get('input_tokens', 0)
                        o_tok = u.get('output_tokens', 0)
                        cc_tok = u.get('cache_creation_input_tokens', 0)
                        cr_tok = u.get('cache_read_input_tokens', 0)

                        input_t += i_tok
                        output_t += o_tok
                        cache_create += cc_tok
                        cache_read += cr_tok

                        # Accumulate per-model tokens
                        mt = model_tokens[model]
                        mt['input'] += i_tok
                        mt['output'] += o_tok
                        mt['cache_create'] += cc_tok
                        mt['cache_read'] += cr_tok

                        # Tool call counting: scan assistant message content
                        content = data['message'].get('content', [])
                        if isinstance(content, list):
                            for block in content:
                                if isinstance(block, dict) and block.get('type') == 'tool_use':
                                    tool_name = block.get('name', 'unknown')
                                    tool_calls[tool_name] += 1

                    # Extract first user message text
                    if data.get('type') in ('human', 'user') and not first_user_msg:
                        msg = data.get('message', '')
                        text = ''
                        if isinstance(msg, dict):
                            content = msg.get('content', '')
                            if isinstance(content, list):
                                for c in content:
                                    if isinstance(c, dict) and c.get('type') == 'text':
                                        text = c.get('text', '')
                                        break
                            elif isinstance(content, str):
                                text = content
                        elif isinstance(msg, str):
                            text = msg

                        text = text.strip().replace('\n', ' ')[:80]
                        # Skip system-injected messages (hooks, reminders)
                        if text and not text.startswith('<') and not text.startswith('['):
                            first_user_msg = text

        except (OSError, PermissionError):
            continue

        if not first_ts or not last_ts:
            continue

        # Check if session overlaps with target date (local time)
        if last_ts < target_start or first_ts >= target_end:
            continue

        # Filter micro-sessions
        if msg_count < min_msgs:
            continue

        # Derive project name from cwd
        project = cwd.rstrip('/').split('/')[-1] if cwd else proj_name.split('-')[-1]

        # Compute per-model cost and session total cost
        session_cost = 0.0
        for model, mt in model_tokens.items():
            rate = price_entry(model)
            session_cost += (mt['input']        / 1_000_000) * rate['input']
            session_cost += (mt['output']       / 1_000_000) * rate['output']
            session_cost += (mt['cache_read']   / 1_000_000) * rate['cache_read']
            session_cost += (mt['cache_create'] / 1_000_000) * rate['cache_create']

        sessions.append({
            'session_id': session_id,
            'project': project,
            'cwd': cwd,
            'start': first_ts.strftime('%H:%M'),
            'end': last_ts.strftime('%H:%M'),
            'messages': msg_count,
            'input_t': input_t,
            'output_t': output_t,
            'cache_create': cache_create,
            'cache_read': cache_read,
            'model_tokens': dict(model_tokens),
            'tool_calls': dict(tool_calls),
            'errors': error_count,
            'cost': session_cost,
            'first_user_msg': first_user_msg,
            'size_kb': round(jsonl.stat().st_size / 1024),
        })

# Sort by start time
sessions.sort(key=lambda x: x['start'])

# Aggregate totals
total_input = sum(s['input_t'] for s in sessions)
total_output = sum(s['output_t'] for s in sessions)
total_cache_create = sum(s['cache_create'] for s in sessions)
total_cache_read = sum(s['cache_read'] for s in sessions)
total_msgs = sum(s['messages'] for s in sessions)
total_tokens = total_input + total_output + total_cache_create + total_cache_read
total_cost = sum(s['cost'] for s in sessions)
total_errors = sum(s['errors'] for s in sessions)

# Aggregate tokens_by_model across all sessions
totals_model_tokens = defaultdict(lambda: {'input': 0, 'output': 0, 'cache_read': 0, 'cache_create': 0})
for s in sessions:
    for model, mt in s['model_tokens'].items():
        tmt = totals_model_tokens[model]
        tmt['input'] += mt['input']
        tmt['output'] += mt['output']
        tmt['cache_read'] += mt['cache_read']
        tmt['cache_create'] += mt['cache_create']

# Aggregate tool_calls across all sessions (Top 10)
totals_tool_calls = defaultdict(int)
for s in sessions:
    for tool, cnt in s['tool_calls'].items():
        totals_tool_calls[tool] += cnt
top_tools = sorted(totals_tool_calls.items(), key=lambda x: -x[1])[:10]

# Per-model cost totals
totals_cost_by_model = {}
for model, mt in totals_model_tokens.items():
    rate = price_entry(model)
    m_cost  = (mt['input']        / 1_000_000) * rate['input']
    m_cost += (mt['output']       / 1_000_000) * rate['output']
    m_cost += (mt['cache_read']   / 1_000_000) * rate['cache_read']
    m_cost += (mt['cache_create'] / 1_000_000) * rate['cache_create']
    totals_cost_by_model[model] = m_cost

# Output YAML
print(f"date: {target_date}")
print(f"timezone: UTC+{tz_offset}")
print(f"sessions:")

for i, s in enumerate(sessions, 1):
    print(f"  - id: {i}")
    print(f"    session_id: {s['session_id']}")
    print(f"    project: {s['project']}")
    print(f"    cwd: {s['cwd']}")
    print(f'    start: "{s["start"]}"')
    print(f'    end: "{s["end"]}"')
    print(f"    messages: {s['messages']}")
    tok_line = f"input: {s['input_t']}, output: {s['output_t']}, cache_create: {s['cache_create']}, cache_read: {s['cache_read']}"
    print(f"    tokens: {{{tok_line}}}")
    # tokens_by_model
    if s['model_tokens']:
        print(f"    tokens_by_model:")
        for model, mt in sorted(s['model_tokens'].items()):
            label = model if model else 'unknown'
            print(f"      {label}:")
            print(f"        input: {mt['input']}")
            print(f"        output: {mt['output']}")
            print(f"        cache_read: {mt['cache_read']}")
            print(f"        cache_create: {mt['cache_create']}")
    # tool_calls
    if s['tool_calls']:
        print(f"    tool_calls:")
        for tool, cnt in sorted(s['tool_calls'].items(), key=lambda x: -x[1]):
            print(f"      {tool}: {cnt}")
    # errors (only if nonzero)
    if s['errors']:
        print(f"    errors: {s['errors']}")
    print(f"    estimated_cost: ${s['cost']:.2f}")
    # Escape YAML special chars in first_user_msg
    msg = s['first_user_msg'].replace('"', '\\"')
    print(f'    first_user_msg: "{msg}"')

print(f"totals:")
print(f"  sessions: {len(sessions)}")
print(f"  messages: {total_msgs}")
print(f"  tokens:")
print(f"    input: {total_input:,}")
print(f"    output: {total_output:,}")
print(f"    cache_create: {total_cache_create:,}")
print(f"    cache_read: {total_cache_read:,}")
print(f"    total: {total_tokens:,}")
if totals_model_tokens:
    print(f"  tokens_by_model:")
    for model, mt in sorted(totals_model_tokens.items()):
        label = model if model else 'unknown'
        print(f"    {label}:")
        print(f"      input: {mt['input']:,}")
        print(f"      output: {mt['output']:,}")
        print(f"      cache_read: {mt['cache_read']:,}")
        print(f"      cache_create: {mt['cache_create']:,}")
print(f"  estimated_cost: ${total_cost:.2f}")
if totals_cost_by_model:
    print(f"  estimated_cost_by_model:")
    for model, c in sorted(totals_cost_by_model.items(), key=lambda x: -x[1]):
        label = model if model else 'unknown'
        print(f"    {label}: ${c:.2f}")
if top_tools:
    print(f"  tool_calls:")
    for tool, cnt in top_tools:
        print(f"    {tool}: {cnt}")
print(f"  errors: {total_errors}")
print(f"  pricing_source: anthropic-public-list")
PYEOF
