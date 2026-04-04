#!/bin/bash
set -euo pipefail

# remind-checkpoint.sh
# TeammateIdle hook: reminds driver to checkpoint after uncheckpointed edits.
# Checks for .dirty flag set by mark-dirty.sh (PreToolUse on Edit/Write).
# The flag is cleared when the teammate runs the session log command.
# Blocking — exits 2 with plain text feedback to prevent idle transition.
# No-op when no active popcorn-xp session or no dirty flag.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/session-common.sh"
px_load_session || exit 0
[ -f "$TEAM_DIR/.shutdown" ] && exit 0

INPUT=$(cat)
AGENT=$(px_normalize_agent "$(echo "$INPUT" | jq -r '.teammate_name // .agent_type // empty' 2>/dev/null || true)")
AGENT_SHORT=$(px_short_agent "$AGENT")
PHASE=$(px_state_field "$AGENT_SHORT" "phase")
[ -n "$PHASE" ] && [ "$PHASE" != "driving" ] && exit 0

[ ! -f "$TEAM_DIR/.dirty" ] && exit 0

# Read edit count if available
COUNT_FILE="$TEAM_DIR/.edit-count"
COUNT=0
[ -f "$COUNT_FILE" ] && COUNT=$(cat "$COUNT_FILE" 2>/dev/null || echo 0)

if [ "$COUNT" -gt 0 ]; then
  echo "Popcorn XP: You have $COUNT file edit(s) since your last checkpoint. Send a checkpoint to your navigator and log it: .popcorn-xp/$TEAM/session log 'what you did'" >&2
else
  echo "Popcorn XP: You edited files since your last checkpoint. Send a checkpoint to your navigator and log it: .popcorn-xp/$TEAM/session log 'what you did'" >&2
fi

# Remove flags so we don't nag on every idle cycle
rm -f "$TEAM_DIR/.dirty"
rm -f "$TEAM_DIR/.edit-count"

exit 2
