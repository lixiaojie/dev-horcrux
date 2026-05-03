#!/bin/bash
# Dev Horcrux Setup — one-time configuration
# Usage: bash setup.sh [output-dir]
# Default output: ~/dev-log

set -e

DEV_HORCRUX_DIR="${1:-$HOME/dev-log}"
CONF="$HOME/.claude/dev-horcrux.conf"
SETTINGS="$HOME/.claude/ft-settings.json"
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "=== Dev Horcrux Setup ==="
echo "Output directory: $DEV_HORCRUX_DIR"
echo "Config file: $CONF"
echo ""

# 1. Create directories
mkdir -p "$DEV_HORCRUX_DIR/insights" "$DEV_HORCRUX_DIR/weekly"
echo "[OK] Created directories"

# 2. Write config
cat > "$CONF" << EOF
# Dev Horcrux Configuration
DEV_HORCRUX_DIR=$DEV_HORCRUX_DIR
WIKILINKS=true
SESSION_FILE=.claude/runtime/last-session.md
INDEX_FILE=~/.claude/global-projects-index.md
EOF
echo "[OK] Wrote config: $CONF"

# 3. Install hooks into settings.json
if [ ! -f "$SETTINGS" ]; then
    echo "{}" > "$SETTINGS"
fi

if jq -e '.hooks.Stop' "$SETTINGS" >/dev/null 2>&1; then
    echo "[SKIP] Stop hook already configured"
else
    jq --arg cmd "bash $SKILL_DIR/scripts/stop-hook.sh" \
       '.hooks.Stop = [{"hooks": [{"type": "command", "command": $cmd, "timeout": 5}]}]' \
       "$SETTINGS" > "${SETTINGS}.tmp" && mv "${SETTINGS}.tmp" "$SETTINGS"
    echo "[OK] Installed Stop hook"
fi

if jq -e '.hooks.SessionStart' "$SETTINGS" >/dev/null 2>&1; then
    echo "[SKIP] SessionStart hook already configured"
else
    jq --arg cmd "bash $SKILL_DIR/scripts/session-start-hook.sh" \
       '.hooks.SessionStart = [{"hooks": [{"type": "command", "command": $cmd, "timeout": 10}]}]' \
       "$SETTINGS" > "${SETTINGS}.tmp" && mv "${SETTINGS}.tmp" "$SETTINGS"
    echo "[OK] Installed SessionStart hook"
fi

# 4. Verify
echo ""
echo "=== Verification ==="
jq -e '.hooks.Stop[0].hooks[0].command' "$SETTINGS" >/dev/null 2>&1 && echo "[OK] Stop hook" || echo "[FAIL] Stop hook"
jq -e '.hooks.SessionStart[0].hooks[0].command' "$SETTINGS" >/dev/null 2>&1 && echo "[OK] SessionStart hook" || echo "[FAIL] SessionStart hook"
[ -f "$CONF" ] && echo "[OK] Config file" || echo "[FAIL] Config file"
[ -d "$DEV_HORCRUX_DIR/insights" ] && echo "[OK] Output directories" || echo "[FAIL] Output directories"

echo ""
echo "=== Done ==="
echo "Dev Horcrux is ready. Restart Claude Code or run /hooks to reload."
echo ""
echo "Commands:"
echo "  Morning: say '开工' or 'morning'"
echo "  Evening: say '收工' or 'wrap up'"
echo "  Weekly:  say '周回顾' or 'weekly review'"
echo ""
echo "=== Optional: Persistent Scheduling ==="
echo "To auto-generate plans and logs daily, run in any Claude Code session:"
echo "  '帮我设置 dev-horcrux 持久调度'"
echo "This creates durable CronCreate jobs (09:05 morning plan, 19:05 evening log)"
echo "with self-renewal to bypass the 7-day expiry. See SKILL.md for details."
