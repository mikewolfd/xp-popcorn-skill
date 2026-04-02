#!/bin/bash
set -euo pipefail

# mark-dirty.sh
# PreToolUse hook on Edit/Write: counts uncheckpointed edits.
# Increments .edit-count each time. After 3+ edits, injects
# additionalContext reminding the driver to checkpoint.
# The counter resets when the teammate runs `session log`.
# Skips .popcorn-xp/ paths (session bookkeeping).
# No-op when no active popcorn-xp session.

POPCORN_DIR="${CLAUDE_PROJECT_DIR:-.}/.popcorn-xp"
TEAM=$(cat "$POPCORN_DIR/.active-team" 2>/dev/null || true)
[ -z "$TEAM" ] && exit 0
[ ! -d "$POPCORN_DIR/$TEAM" ] && exit 0

# Read file_path from stdin (PreToolUse input)
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)

# Skip session bookkeeping files
case "$FILE_PATH" in
  */.popcorn-xp/*) exit 0 ;;
esac

COUNT_FILE="$POPCORN_DIR/$TEAM/.edit-count"
DIRTY_FILE="$POPCORN_DIR/$TEAM/.dirty"

# Increment counter
COUNT=0
[ -f "$COUNT_FILE" ] && COUNT=$(cat "$COUNT_FILE" 2>/dev/null || echo 0)
COUNT=$((COUNT + 1))
echo "$COUNT" > "$COUNT_FILE"

# Always set dirty flag for remind-checkpoint.sh
touch "$DIRTY_FILE"

# After 3+ uncheckpointed edits, inject a soft reminder
if [ "$COUNT" -ge 3 ]; then
  cat <<EOJSON
{"additionalContext":"Popcorn XP: You have $COUNT file edits since your last checkpoint. Send a checkpoint to your navigator and log it: .popcorn-xp/$TEAM/session log 'what you did'"}
EOJSON
fi

exit 0
