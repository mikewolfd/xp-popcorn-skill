#!/bin/bash
set -euo pipefail

# notify-retro-received.sh
# FileChanged hook: when a .retro-*.md file appears, notify the lead
# how many retros have been collected out of expected.
# No-op when no active popcorn-xp session.

POPCORN_DIR="${CLAUDE_PROJECT_DIR:-.}/.popcorn-xp"
TEAM=$(cat "$POPCORN_DIR/.active-team" 2>/dev/null || true)
[ -z "$TEAM" ] && exit 0

TEAM_DIR="$POPCORN_DIR/$TEAM"
[ ! -d "$TEAM_DIR" ] && exit 0

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.file_path // empty' 2>/dev/null || true)
[ -z "$FILE_PATH" ] && exit 0

# Only react to retro files
BASENAME=$(basename "$FILE_PATH")
if echo "$BASENAME" | grep -qE '^\.retro-.*\.md$'; then
  AGENT=$(echo "$BASENAME" | sed 's/^\.retro-\(.*\)\.md$/\1/')

  # Count collected retros
  COLLECTED=$(ls "$TEAM_DIR"/.retro-*.md 2>/dev/null | wc -l | tr -d ' ')

  echo "{\"additionalContext\":\"Retro file received: .retro-$AGENT.md. $COLLECTED retro(s) collected so far. Check if all expected retros are in before writing RETRO.md.\"}"
fi

exit 0
