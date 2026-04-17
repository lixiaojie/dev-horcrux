#!/bin/bash
# Dev Horcrux Session Discovery
# Scans all JSONL session files and outputs structured session data for a given date
# Usage: discover-sessions.sh YYYY-MM-DD [timezone-offset] [--min-msgs=N]
# Output: YAML-formatted session list to stdout

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

target_date = sys.argv[1]
tz_offset = int(sys.argv[2])
min_msgs = int(sys.argv[3])

LOCAL_TZ = timezone(timedelta(hours=tz_offset))
target_start = datetime.strptime(target_date, '%Y-%m-%d').replace(tzinfo=LOCAL_TZ)
target_end = target_start + timedelta(days=1)

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

                    if data.get('type') == 'assistant' and 'message' in data:
                        msg_count += 1
                        u = data['message'].get('usage', {})
                        input_t += u.get('input_tokens', 0)
                        output_t += u.get('output_tokens', 0)
                        cache_create += u.get('cache_creation_input_tokens', 0)
                        cache_read += u.get('cache_read_input_tokens', 0)

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

# Cost: input=$3/M, output=$15/M, cache_creation=$3.75/M, cache_read=$0.30/M
cost = (total_input * 3 + total_output * 15 + total_cache_create * 3.75 + total_cache_read * 0.30) / 1_000_000

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
print(f"  estimated_cost: ${cost:.2f}")
PYEOF
