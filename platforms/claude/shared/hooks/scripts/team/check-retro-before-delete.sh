#!/bin/bash
set -euo pipefail

# check-retro-before-delete.sh
# PreToolUse hook on TeamDelete: blocks if RETRO.md doesn't exist
# or doesn't have meaningful content (at least 5 lines). The retro happens BEFORE the summary,
# BEFORE shutdown, BEFORE cleanup — it's mandatory.
# No-op when no active popcorn-xp session directory exists.
# Subagent mode: no-op — closeout uses session close-check / session close (which enforces RETRO.md ≥5 lines), not TeamDelete.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../../../.." && pwd)"
# shellcheck source=../../../../../../shared/runtime/lib/session-common.sh
source "$REPO_ROOT/shared/runtime/lib/session-common.sh"

POPCORN_DIR="${CLAUDE_PROJECT_DIR:-.}/.popcorn-xp"
TEAM=$(cat "$POPCORN_DIR/.active-team" 2>/dev/null || true)
[ -z "$TEAM" ] && exit 0

TEAM_DIR="$POPCORN_DIR/$TEAM"
[ ! -d "$TEAM_DIR" ] && exit 0

px_load_session || exit 0
px_is_subagent_mode && exit 0

# Check if RETRO.md exists
if [ ! -f "$TEAM_DIR/RETRO.md" ]; then
  echo "No .popcorn-xp/$TEAM/RETRO.md found. The retrospective is mandatory — write it before cleaning up the team. Include: what worked, what didn't, rotation assessment, advice system assessment, and recommendations for next session." >&2
  exit 2
fi

# Check if RETRO.md has real content (not just a header)
line_count=$(wc -l < "$TEAM_DIR/RETRO.md" | tr -d ' ')
if [ "$line_count" -lt 5 ]; then
  echo ".popcorn-xp/$TEAM/RETRO.md exists but looks empty or stub-only. Write a real retrospective before cleaning up the team." >&2
  exit 2
fi

exit 0
