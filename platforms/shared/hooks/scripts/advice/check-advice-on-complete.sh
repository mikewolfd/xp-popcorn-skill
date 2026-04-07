#!/bin/bash
set -euo pipefail

# check-advice-on-complete.sh
# TaskCompleted hook: ensures the driver has ENGAGED with advice, not that they've obeyed it
#   - Open OBJECTIONs → BLOCK — must engage (fix OR reject with reasoning)
#   - Open SMELLs/STEERs/FYIs → WARN — your call, but you should know they're there
# No-op when no active popcorn-xp session

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../../.." && pwd)"
# shellcheck source=../../../../shared/runtime/lib/session-common.sh
source "$REPO_ROOT/shared/runtime/lib/session-common.sh"
px_load_session || exit 0

ADVICE="$TEAM_DIR/ADVICE.md"
[ ! -f "$ADVICE" ] && exit 0

# Append-only ledger: advice is "### TYPE ID — open", resolutions are "### ID — OUTCOME"
# An item is unresolved if its ID appears in an "— open" line but NOT in an "— OUTCOME" line.

unresolved=$(px_unresolved_advice "$ADVICE" OBJECTION | awk '{print $2}')
if [ -n "$unresolved" ] && [ "$unresolved" -gt 0 ]; then
  echo "${unresolved} unresolved OBJECTION(s) in .popcorn-xp/$TEAM/ADVICE.md. Engage before completing. Fix the issue if they're right, or reject with your reasoning if they're not. Use: .popcorn-xp/$TEAM/session resolve OBJ-X-XX FIXED|REJECTED 'detail'" >&2
  exit 2
fi

# Count unresolved non-blocking items
parts=""
while IFS=' ' read -r TYPE count; do
  [ -n "$TYPE" ] || continue
  [ -n "$parts" ] && parts="$parts, "
  parts="${parts}${count} ${TYPE}(s)"
done < <(px_unresolved_advice "$ADVICE" SMELL STEER FYI)

if [ -n "$parts" ]; then
  echo "{\"additionalContext\":\"${parts} still unresolved in .popcorn-xp/$TEAM/ADVICE.md. These are input, not instructions — read them and use your judgment. Resolve via session script if you have time, but don't let them hold up good work.\"}"
fi

exit 0
