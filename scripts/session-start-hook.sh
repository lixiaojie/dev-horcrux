#!/bin/bash
# Dev Horcrux SessionStart Hook — detects missing horcruxes and morning plans
# Reads config from ~/.claude/dev-horcrux.conf

CONF="$HOME/.claude/dev-horcrux.conf"
if [ ! -f "$CONF" ]; then
    CONF="$HOME/.claude/dev-journal.conf"
    [ ! -f "$CONF" ] && exit 0
fi

# shellcheck source=/dev/null
source "$CONF"

DIR="${DEV_HORCRUX_DIR:-$DEV_JOURNAL_DIR}"
[ -z "$DIR" ] && exit 0

LAST_DATE=$(cat ~/.claude/last-active-date 2>/dev/null)
TODAY=$(date +%Y-%m-%d)
MESSAGES=""

# 1. Check if last active date has a horcrux (backfill detection)
if [ -n "$LAST_DATE" ] && [ "$LAST_DATE" != "$TODAY" ]; then
    if [ ! -f "$DIR/$LAST_DATE.md" ]; then
        MESSAGES="[DEV-LOG BACKFILL] $LAST_DATE had active sessions but no horcrux was created. Please generate $DIR/$LAST_DATE.md and $DIR/insights/$LAST_DATE.md from last-session.md and project index."
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

# Output JSON if there are messages
if [ -n "$MESSAGES" ]; then
    ESCAPED=$(echo -e "$MESSAGES" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip()))")
    echo "{\"hookSpecificOutput\":{\"hookEventName\":\"SessionStart\",\"additionalContext\":$ESCAPED}}"
fi
