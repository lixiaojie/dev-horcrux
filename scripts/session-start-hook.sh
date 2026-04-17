#!/bin/bash
# Dev Horcrux SessionStart Hook — detects missing horcruxes and morning plans
# Scans activity.log for recent 7 days, checks for missing logs (not just yesterday)
# Reads config from ~/.claude/dev-horcrux.conf

CONF="$HOME/.claude/dev-horcrux.conf"
[ ! -f "$CONF" ] && exit 0

# shellcheck source=/dev/null
source "$CONF"

DIR="$DEV_HORCRUX_DIR"
[ -z "$DIR" ] && exit 0

TODAY=$(date +%Y-%m-%d)
ACTIVITY_LOG="$HOME/.claude/session-activity.log"
MESSAGES=""

# 1. Scan activity.log for dates with activity but no log file (last 7 days)
if [ -f "$ACTIVITY_LOG" ]; then
    # Get unique dates from activity log (last 7 days only)
    MISSING_DATES=""
    CUTOFF=$(date -v-7d +%Y-%m-%d 2>/dev/null || date -d "7 days ago" +%Y-%m-%d 2>/dev/null)

    # Extract unique dates from activity log, filter to recent 7 days and not today
    ACTIVE_DATES=$(cut -d'T' -f1 "$ACTIVITY_LOG" | sort -u | while read -r d; do
        [ -z "$d" ] && continue
        [ "$d" = "$TODAY" ] && continue
        # Only include dates >= cutoff
        if [ "$d" \> "$CUTOFF" ] || [ "$d" = "$CUTOFF" ]; then
            echo "$d"
        fi
    done)

    for d in $ACTIVE_DATES; do
        if [ ! -f "$DIR/$d.md" ]; then
            if [ -z "$MISSING_DATES" ]; then
                MISSING_DATES="$d"
            else
                MISSING_DATES="$MISSING_DATES, $d"
            fi
        fi
    done

    if [ -n "$MISSING_DATES" ]; then
        MESSAGES="[DEV-LOG BACKFILL] Missing logs for: $MISSING_DATES. Please generate using: bash ~/.claude/skills/dev-horcrux/scripts/discover-sessions.sh <date> for each missing date, then write the log files."
    fi
fi

# 2. Check if today's morning plan exists
if [ ! -f "$DIR/${TODAY}-plan.md" ]; then
    if [ -n "$MESSAGES" ]; then
        MESSAGES="$MESSAGES\n[MORNING PLAN] Today's plan not yet generated. Please create $DIR/${TODAY}-plan.md."
    else
        MESSAGES="[MORNING PLAN] Today's plan not yet generated. Please create $DIR/${TODAY}-plan.md."
    fi
fi

# 3. Auto-load project-relevant memories based on CWD
CWD=$(pwd)
PROJECT_NAME=$(basename "$CWD")
MEMORY_DIR="$HOME/.claude/projects/-Users-admin-Documents-claude-project/memory"

if [ -d "$MEMORY_DIR" ]; then
    # Search for memories matching current project directory name
    RELEVANT=$(grep -rli "$PROJECT_NAME" "$MEMORY_DIR"/*.md 2>/dev/null | grep -v "MEMORY.md" | head -3 || true)
    if [ -n "$RELEVANT" ]; then
        MEMORY_HINTS="[MEMORY CONTEXT] Relevant memories for $PROJECT_NAME:"
        for f in $RELEVANT; do
            BNAME=$(basename "$f" .md)
            # Extract description from frontmatter
            DESC=$(grep -A1 "^description:" "$f" 2>/dev/null | head -1 | sed 's/^description: //' || echo "")
            MEMORY_HINTS="$MEMORY_HINTS\n- $BNAME: $DESC (read with: bash ~/.claude/hooks/memory-search.sh '$PROJECT_NAME')"
        done
        if [ -n "$MESSAGES" ]; then
            MESSAGES="$MESSAGES\n$MEMORY_HINTS"
        else
            MESSAGES="$MEMORY_HINTS"
        fi
    fi
fi

# Output JSON if there are messages
if [ -n "$MESSAGES" ]; then
    ESCAPED=$(echo -e "$MESSAGES" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip()))")
    echo "{\"hookSpecificOutput\":{\"hookEventName\":\"SessionStart\",\"additionalContext\":$ESCAPED}}"
fi
