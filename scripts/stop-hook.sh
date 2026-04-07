#!/bin/bash
# Dev Journal Stop Hook — records timestamp + working directory to activity log
# Runs on every Claude stop — must be extremely lightweight (<5ms)
NOW=$(date +%Y-%m-%dT%H:%M:%S)
CWD=$(pwd)
echo "$NOW|$CWD" >> ~/.claude/session-activity.log
echo "$(date +%Y-%m-%d)" > ~/.claude/last-active-date
