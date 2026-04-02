#!/bin/bash
set -euo pipefail

# notify-retro-written.sh
# PostToolUse(Write) hook: when a teammate writes a .retro-*.md file,
# nudge them to SendMessage the lead to confirm.
# No-op when no active popcorn-xp session.

POPCORN_DIR="${CLAUDE_PROJECT_DIR:-.}/.popcorn-xp"
TEAM=$(cat "$POPCORN_DIR/.active-team" 2>/dev/null || true)
[ -z "$TEAM" ] && exit 0

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)
[ -z "$FILE_PATH" ] && exit 0

# Check if the written file is a retro file
if echo "$FILE_PATH" | grep -qE '\.retro-[^/]+\.md$'; then
  AGENT=$(echo "$FILE_PATH" | sed 's/.*\.retro-\(.*\)\.md/\1/')
  echo "{\"additionalContext\":\"You just wrote your retro file (.retro-$AGENT.md). SendMessage the lead to confirm: SendMessage(to: 'team-lead', summary: 'retro submitted', message: 'Retro submitted: .retro-$AGENT.md')\"}"
fi

exit 0
