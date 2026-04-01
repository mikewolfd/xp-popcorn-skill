#!/bin/bash
set -euo pipefail

# check-objections.sh
# SubagentStop hook (backup): blocks if open OBJECTIONs exist
# The primary enforcement is TaskCompleted — this catches the edge case
# where a teammate tries to stop without completing the task
# No-op when no active popcorn-xp session

ADVICE="${CLAUDE_PROJECT_DIR:-.}/.popcorn-xp/ADVICE.md"

[ ! -f "$ADVICE" ] && exit 0

open_section=$(sed -n '/^## Open$/,/^## Resolved$/p' "$ADVICE" 2>/dev/null || true)

if echo "$open_section" | grep -q "^### OBJECTION"; then
  echo '{"decision":"block","reason":"Open OBJECTIONs exist in .popcorn-xp/ADVICE.md. You must resolve all OBJECTIONs before stopping — either fix the issue or explicitly reject with a stated reason."}' >&2
  exit 2
fi

exit 0
