#!/bin/bash
set -euo pipefail

# check-objections.sh
# SubagentStop hook (backup): blocks if unresolved OBJECTIONs exist
# The primary enforcement is TaskCompleted — this catches the edge case
# where a teammate tries to stop without completing the task
# No-op when no active popcorn-xp session

POPCORN_DIR="${CLAUDE_PROJECT_DIR:-.}/.popcorn-xp"
TEAM=$(cat "$POPCORN_DIR/.active-team" 2>/dev/null || true)
[ -z "$TEAM" ] && exit 0

ADVICE="$POPCORN_DIR/$TEAM/ADVICE.md"
[ ! -f "$ADVICE" ] && exit 0

# Check for unresolved OBJECTIONs
open_obj_ids=$(grep -oE '### OBJECTION ([^ ]+) — open' "$ADVICE" | sed 's/### OBJECTION \([^ ]*\) — open/\1/' || true)

for id in $open_obj_ids; do
  if ! grep -iqE "^### $id — (FIXED|REJECTED|INCORPORATED|NOTED)" "$ADVICE"; then
    echo "Unresolved OBJECTIONs exist in ADVICE.md. You must resolve all OBJECTIONs before stopping — either fix the issue or explicitly reject with a stated reason." >&2
    exit 2
  fi
done

exit 0
