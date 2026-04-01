#!/bin/bash
set -euo pipefail

# init-session.sh
# PreToolUse hook on TaskUpdate: auto-creates .popcorn-xp/ directory and
# session files when a task is first marked in_progress.
# Replaces the manual "create .popcorn-xp/ if it doesn't exist" instruction
# in the driver prompt template.
# No-op if .popcorn-xp/ already exists.

POPCORN_DIR="${CLAUDE_PROJECT_DIR:-.}/.popcorn-xp"

# Only initialize if the directory doesn't exist yet
[ -d "$POPCORN_DIR" ] && exit 0

# Check if this is a status change to in_progress
INPUT=$(cat)
STATUS=$(echo "$INPUT" | jq -r '.tool_input.status // empty' 2>/dev/null)
[ "$STATUS" != "in_progress" ] && exit 0

mkdir -p "$POPCORN_DIR"
echo "# Popcorn XP Log" > "$POPCORN_DIR/LOG.md"
printf "# Popcorn XP Advice\n\n## Open\n\n## Resolved\n" > "$POPCORN_DIR/ADVICE.md"

exit 0
