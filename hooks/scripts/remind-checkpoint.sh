#!/bin/bash
set -euo pipefail

# remind-checkpoint.sh
# TeammateIdle hook: reminds driver to checkpoint after uncheckpointed edits.
# Counts EDIT events in context-store.log since the last checkpoint cursor.
# Blocking — exits 2 with plain text feedback to prevent idle transition.
# No-op when no active popcorn-xp session or no pending edits.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/session-common.sh"
source "$SCRIPT_DIR/context-store-log.sh"
px_load_session || exit 0
[ -f "$TEAM_DIR/.shutdown" ] && exit 0

INPUT=$(cat)
AGENT=$(px_normalize_agent "$(echo "$INPUT" | jq -r '.teammate_name // .agent_type // empty' 2>/dev/null || true)")
AGENT_SHORT=$(px_short_agent "$AGENT")
PHASE=$(px_state_field "$AGENT_SHORT" "phase")
[ -n "$PHASE" ] && [ "$PHASE" != "driving" ] && exit 0

LOG_FILE=$(cs_log_file)
CURSOR_FILE=$(cs_checkpoint_cursor_file "$TEAM_DIR")
COUNT=$(cs_edit_count_since_cursor "$LOG_FILE" "$CURSOR_FILE")
[ "$COUNT" -eq 0 ] && exit 0

if [ "$COUNT" -gt 0 ]; then
  echo "Popcorn XP: You have $COUNT file edit(s) since your last checkpoint. Send a checkpoint to your navigator and log it: .popcorn-xp/$TEAM/session log 'what you did'" >&2
else
  echo "Popcorn XP: You edited files since your last checkpoint. Send a checkpoint to your navigator and log it: .popcorn-xp/$TEAM/session log 'what you did'" >&2
fi

exit 2
