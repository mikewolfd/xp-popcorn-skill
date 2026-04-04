#!/bin/bash
set -euo pipefail

# remind-unread-advice.sh
# TeammateIdle hook: reminds teammate of any unresolved advice when they go idle
# Blocking — exits 2 with plain text feedback to prevent idle transition
# No-op when no active popcorn-xp session

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/session-common.sh"
px_load_session || exit 0
[ -f "$TEAM_DIR/.shutdown" ] && exit 0

ADVICE="$TEAM_DIR/ADVICE.md"
[ ! -f "$ADVICE" ] && exit 0

INPUT=$(cat)
AGENT=$(px_normalize_agent "$(echo "$INPUT" | jq -r '.teammate_name // .agent_type // empty' 2>/dev/null || true)")
AGENT_SHORT=$(px_short_agent "$AGENT")
PHASE=$(px_state_field "$AGENT_SHORT" "phase")
[ "$PHASE" = "waiting_on_driver" ] && [ -z "$(grep -oE '### OBJECTION ([^ ]+) — open' "$ADVICE" || true)" ] && exit 0

# Count unresolved items by type
total=0
summary=""
for TYPE in "OBJECTION" "SMELL" "STEER" "FYI"; do
  open_ids=$(grep -oE "### $TYPE ([^ ]+) — open" "$ADVICE" | sed 's/### [^ ]* \([^ ]*\) — open/\1/' || true)
  count=0
  for id in $open_ids; do
    if ! grep -iqE "^### $id — (FIXED|REJECTED|INCORPORATED|NOTED)" "$ADVICE"; then
      count=$((count + 1))
    fi
  done
  if [ "$count" -gt 0 ]; then
    total=$((total + count))
    [ -n "$summary" ] && summary="$summary, "
    summary="${summary}${count} ${TYPE}(s)"
  fi
done

[ "$total" -eq 0 ] && exit 0

echo "Popcorn XP: ${total} unresolved advice item(s) in .popcorn-xp/$TEAM/ADVICE.md (${summary}). OBJECTIONs must be resolved before task completion. SMELLs, STEERs, and FYIs are your call — resolve if you can, but don't let them hold up good work." >&2

exit 2
