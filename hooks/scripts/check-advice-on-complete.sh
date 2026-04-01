#!/bin/bash
set -euo pipefail

# check-advice-on-complete.sh
# TaskCompleted hook: ensures the driver has ENGAGED with advice, not that they've obeyed it
#   - Open OBJECTIONs → BLOCK — must engage (fix OR reject with reasoning)
#   - Open SMELLs/STEERs/FYIs → WARN — your call, but you should know they're there
# No-op when no active popcorn-xp session

ADVICE="${CLAUDE_PROJECT_DIR:-.}/.popcorn-xp/ADVICE.md"

[ ! -f "$ADVICE" ] && exit 0

open_section=$(sed -n '/^## Open$/,/^## Resolved$/p' "$ADVICE" 2>/dev/null || true)

# Count open items by type
# Match both "### OBJECTION" (prescribed format) and bare "OBJECTION OBJ-" / "OBJ-" (actual usage)
objections=$(echo "$open_section" | grep -ciE "^(###\s+)?OBJECTION|^(###\s+)?OBJ-" 2>/dev/null || true)
smells=$(echo "$open_section" | grep -ciE "^(###\s+)?SMELL|^(###\s+)?SML-" 2>/dev/null || true)
steers=$(echo "$open_section" | grep -ciE "^(###\s+)?STEER|^(###\s+)?STR-" 2>/dev/null || true)
fyis=$(echo "$open_section" | grep -ciE "^(###\s+)?FYI" 2>/dev/null || true)

# OBJECTIONs block — someone claims something is factually wrong.
# You must engage: fix the issue OR reject with your reasoning. Both are valid.
if [ "$objections" -gt 0 ]; then
  echo "{\"decision\":\"block\",\"reason\":\"${objections} open OBJECTION(s) in .popcorn-xp/ADVICE.md. Someone thinks something is wrong — engage with it before completing. Fix the issue if they're right, or reject with your reasoning if they're not. Both are valid outcomes.\"}" >&2
  exit 2
fi

# Everything else is advice, not instructions. Remind, don't block.
pending=$((smells + steers + fyis))
if [ "$pending" -gt 0 ]; then
  parts=""
  [ "$smells" -gt 0 ] && parts="${smells} SMELL(s)"
  [ "$steers" -gt 0 ] && { [ -n "$parts" ] && parts="$parts, "; parts="${parts}${steers} STEER(s)"; }
  [ "$fyis" -gt 0 ] && { [ -n "$parts" ] && parts="$parts, "; parts="${parts}${fyis} FYI(s)"; }
  echo "{\"systemMessage\":\"${parts} still open in .popcorn-xp/ADVICE.md. These are input, not instructions — read them and use your judgment. Resolve in ADVICE.md if you have time, but don't let them hold up good work.\"}"
fi

exit 0
