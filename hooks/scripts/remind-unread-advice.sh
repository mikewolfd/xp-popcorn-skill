#!/bin/bash
set -euo pipefail

# remind-unread-advice.sh
# TeammateIdle hook: reminds teammate of any unresolved advice when they go idle
# Non-blocking — just a nudge via systemMessage
# No-op when no active popcorn-xp session

POPCORN_DIR="${CLAUDE_PROJECT_DIR:-.}/.popcorn-xp"
TEAM=$(cat "$POPCORN_DIR/.active-team" 2>/dev/null || true)
[ -z "$TEAM" ] && exit 0

ADVICE="$POPCORN_DIR/$TEAM/ADVICE.md"
[ ! -f "$ADVICE" ] && exit 0

# Count unresolved items by type
total=0
summary=""
for type_info in "OBJECTION:OBJ" "SMELL:SML" "STEER:STR" "FYI:FYI"; do
  TYPE="${type_info%%:*}"
  PREFIX="${type_info##*:}"
  open_ids=$(grep -oE "### $TYPE ($PREFIX-[0-9]+-[0-9]+) — open" "$ADVICE" | grep -oE "$PREFIX-[0-9]+-[0-9]+" || true)
  count=0
  for id in $open_ids; do
    if ! grep -qE "^### $id — (FIXED|REJECTED|INCORPORATED|NOTED)" "$ADVICE"; then
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

echo "{\"systemMessage\":\"Popcorn XP: ${total} unresolved advice item(s) in .popcorn-xp/$TEAM/ADVICE.md (${summary}). OBJECTIONs must be resolved before task completion. SMELLs, STEERs, and FYIs are your call — resolve if you can, but don't let them hold up good work.\"}"

exit 0
