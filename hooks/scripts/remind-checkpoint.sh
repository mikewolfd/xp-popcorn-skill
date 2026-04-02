#!/bin/bash
set -euo pipefail

# remind-checkpoint.sh
# TeammateIdle hook: reminds driver to checkpoint after uncheckpointed edits.
# Checks for .dirty flag set by mark-dirty.sh (PreToolUse on Edit/Write).
# The flag is cleared when the teammate runs the session log command.
# Non-blocking — just a nudge via systemMessage.
# No-op when no active popcorn-xp session or no dirty flag.

POPCORN_DIR="${CLAUDE_PROJECT_DIR:-.}/.popcorn-xp"
TEAM=$(cat "$POPCORN_DIR/.active-team" 2>/dev/null || true)
[ -z "$TEAM" ] && exit 0

[ ! -f "$POPCORN_DIR/$TEAM/.dirty" ] && exit 0

echo "{\"systemMessage\":\"Popcorn XP: You edited files since your last checkpoint. Send a checkpoint to your navigator and log it: .popcorn-xp/$TEAM/session log 'what you did'\"}"

# Remove flag so we don't nag on every idle cycle
rm -f "$POPCORN_DIR/$TEAM/.dirty"

exit 0
