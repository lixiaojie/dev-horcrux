#!/bin/bash
# Dev Journal Stop Hook — records timestamp + working directory to activity log
# Runs on every Claude stop — must be extremely lightweight (<5ms)
NOW=$(date +%Y-%m-%dT%H:%M:%S)
CWD=$(pwd)
echo "$NOW|$CWD" >> ~/.claude/session-activity.log
echo "$(date +%Y-%m-%d)" > ~/.claude/last-active-date

# --- Obsidian vault claude-system backup ---
VAULT_SYSTEM="$HOME/Documents/obsidian-vault/claude-system"
if [ -d "$VAULT_SYSTEM" ]; then
  rsync -a --delete \
    --include='CLAUDE.md' \
    --include='assistant-core.md' \
    --include='bootstrap-rules.md' \
    --include='memory-policy.md' \
    --include='project-filesystem.md' \
    --include='global-*.md' \
    --include='settings.json' \
    --include='ft-settings.json' \
    --include='dev-horcrux.conf' \
    --include='skills/' \
    --include='skills/dev-horcrux/' \
    --include='skills/dev-horcrux/**' \
    --exclude='*' \
    "$HOME/.claude/" "$VAULT_SYSTEM/" 2>/dev/null
fi
