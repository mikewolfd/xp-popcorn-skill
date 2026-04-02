#!/bin/bash
set -euo pipefail

# check-advice-on-complete.sh
# TaskCompleted hook: ensures the driver has ENGAGED with advice, not that they've obeyed it
#   - Open OBJECTIONs → BLOCK — must engage (fix OR reject with reasoning)
#   - Open SMELLs/STEERs/FYIs → WARN — your call, but you should know they're there
# No-op when no active popcorn-xp session

POPCORN_DIR="${CLAUDE_PROJECT_DIR:-.}/.popcorn-xp"
TEAM=$(cat "$POPCORN_DIR/.active-team" 2>/dev/null || true)
[ -z "$TEAM" ] && exit 0

ADVICE="$POPCORN_DIR/$TEAM/ADVICE.md"
[ ! -f "$ADVICE" ] && exit 0

# Append-only ledger: advice is "### TYPE ID — open", resolutions are "### ID — OUTCOME"
# An item is unresolved if its ID appears in an "— open" line but NOT in an "— OUTCOME" line.

# Extract all open OBJECTION IDs
open_obj_ids=$(grep -oE '### OBJECTION (OBJ-[0-9]+-[0-9]+) — open' "$ADVICE" | grep -oE 'OBJ-[0-9]+-[0-9]+' || true)

unresolved=0
for id in $open_obj_ids; do
  if ! grep -qE "^### $id — (FIXED|REJECTED|INCORPORATED|NOTED)" "$ADVICE"; then
    unresolved=$((unresolved + 1))
  fi
done

if [ "$unresolved" -gt 0 ]; then
  echo "{\"decision\":\"block\",\"reason\":\"${unresolved} unresolved OBJECTION(s) in .popcorn-xp/$TEAM/ADVICE.md. Someone thinks something is wrong — engage with it before completing. Fix the issue if they're right, or reject with your reasoning if they're not. Both are valid outcomes. Use: .popcorn-xp/$TEAM/session resolve OBJ-X-XX FIXED|REJECTED 'detail'\"}" >&2
  exit 2
fi

# Count unresolved non-blocking items
pending=0
parts=""
for type_prefix in "SMELL:SML" "STEER:STR" "FYI:FYI"; do
  TYPE="${type_prefix%%:*}"
  PREFIX="${type_prefix##*:}"
  open_ids=$(grep -oE "### $TYPE ($PREFIX-[0-9]+-[0-9]+) — open" "$ADVICE" | grep -oE "$PREFIX-[0-9]+-[0-9]+" || true)
  count=0
  for id in $open_ids; do
    if ! grep -qE "^### $id — (FIXED|REJECTED|INCORPORATED|NOTED)" "$ADVICE"; then
      count=$((count + 1))
    fi
  done
  if [ "$count" -gt 0 ]; then
    pending=$((pending + count))
    [ -n "$parts" ] && parts="$parts, "
    parts="${parts}${count} ${TYPE}(s)"
  fi
done

if [ "$pending" -gt 0 ]; then
  echo "{\"systemMessage\":\"${parts} still unresolved in .popcorn-xp/$TEAM/ADVICE.md. These are input, not instructions — read them and use your judgment. Resolve via session script if you have time, but don't let them hold up good work.\"}"
fi

exit 0
