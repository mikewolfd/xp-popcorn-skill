#!/bin/bash
set -euo pipefail

# remind-unread-advice.sh
# TeammateIdle hook: reminds teammate of any open advice when they go idle
# Non-blocking — just a nudge via systemMessage
# No-op when no active popcorn-xp session

ADVICE="${CLAUDE_PROJECT_DIR:-.}/.popcorn-xp/ADVICE.md"

[ ! -f "$ADVICE" ] && exit 0

open_section=$(sed -n '/^## Open$/,/^## Resolved$/p' "$ADVICE" 2>/dev/null || true)

# Count all open items
total=$(echo "$open_section" | grep -c "^### " 2>/dev/null || true)

[ "$total" -eq 0 ] && exit 0

# Break down by type
objections=$(echo "$open_section" | grep -c "^### OBJECTION" 2>/dev/null || true)
smells=$(echo "$open_section" | grep -c "^### SMELL" 2>/dev/null || true)
steers=$(echo "$open_section" | grep -c "^### STEER" 2>/dev/null || true)
fyis=$(echo "$open_section" | grep -c "^### FYI" 2>/dev/null || true)

summary=""
[ "$objections" -gt 0 ] && summary="${objections} OBJECTION(s)"
[ "$smells" -gt 0 ] && { [ -n "$summary" ] && summary="$summary, "; summary="${summary}${smells} SMELL(s)"; }
[ "$steers" -gt 0 ] && { [ -n "$summary" ] && summary="$summary, "; summary="${summary}${steers} STEER(s)"; }
[ "$fyis" -gt 0 ] && { [ -n "$summary" ] && summary="$summary, "; summary="${summary}${fyis} FYI(s)"; }

echo "{\"systemMessage\":\"Popcorn XP: ${total} open advice item(s) in .popcorn-xp/ADVICE.md (${summary}). Read the file and resolve items before your next action — OBJECTIONs and SMELLs must be resolved before task completion.\"}"

exit 0
