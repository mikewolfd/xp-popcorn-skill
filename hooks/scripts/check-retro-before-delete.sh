#!/bin/bash
set -euo pipefail

# check-retro-before-delete.sh
# PreToolUse hook on TeamDelete: blocks if RETRO.md doesn't exist
# or hasn't been updated this session. The retro happens BEFORE the summary,
# BEFORE shutdown, BEFORE cleanup — it's mandatory.
# No-op when no active popcorn-xp session directory exists.

POPCORN_DIR="${CLAUDE_PROJECT_DIR:-.}/.popcorn-xp"
TEAM=$(cat "$POPCORN_DIR/.active-team" 2>/dev/null || true)
[ -z "$TEAM" ] && exit 0

TEAM_DIR="$POPCORN_DIR/$TEAM"
[ ! -d "$TEAM_DIR" ] && exit 0

# Check if RETRO.md exists
if [ ! -f "$TEAM_DIR/RETRO.md" ]; then
  echo "{\"decision\":\"block\",\"reason\":\"No .popcorn-xp/$TEAM/RETRO.md found. The retrospective is mandatory — write it before cleaning up the team. Include: what worked, what didn't, rotation assessment, advice system assessment, and recommendations for next session.\"}" >&2
  exit 2
fi

# Check if RETRO.md has real content (not just a header)
line_count=$(wc -l < "$TEAM_DIR/RETRO.md" | tr -d ' ')
if [ "$line_count" -lt 5 ]; then
  echo "{\"decision\":\"block\",\"reason\":\".popcorn-xp/$TEAM/RETRO.md exists but looks empty or stub-only. Write a real retrospective before cleaning up the team.\"}" >&2
  exit 2
fi

exit 0
