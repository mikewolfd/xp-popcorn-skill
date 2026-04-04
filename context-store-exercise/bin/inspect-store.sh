#!/bin/bash
set -euo pipefail

# inspect-store.sh — Pretty-print the context store during or after a session.
# Run from the project root: bash bin/inspect-store.sh

STORE=".popcorn-xp/context-store.json"

if [ ! -f "$STORE" ]; then
  echo "No context store found at $STORE"
  echo "Run a popcorn-xp session first."
  exit 1
fi

echo "=== Context Store ==="
echo ""

jq -r '
  to_entries[] |
  "\(.key)\n  read_by:   \(.value.read_by)  at \(.value.read_at)" +
  (if .value.dirty then "\n  DIRTY:     edited by \(.value.edited_by // "unknown") at \(.value.edited_at // "unknown")" else "\n  status:    CLEAN" end) +
  (if .value.offset then "\n  range:     offset=\(.value.offset) limit=\(.value.limit)" else "" end) +
  "\n"
' "$STORE"

TOTAL=$(jq 'length' "$STORE")
DIRTY=$(jq '[.[] | select(.dirty == true)] | length' "$STORE")
CLEAN=$(jq '[.[] | select(.dirty == false)] | length' "$STORE")
AGENTS=$(jq '[.[].read_by] | unique | length' "$STORE")

echo "--- Summary ---"
echo "Total files:    $TOTAL"
echo "Clean:          $CLEAN"
echo "Dirty:          $DIRTY"
echo "Unique readers: $AGENTS"

# Show log tail if it exists
LOG=".popcorn-xp/context-store.log"
if [ -f "$LOG" ]; then
  LINES=$(wc -l < "$LOG" | tr -d ' ')
  echo ""
  echo "=== Event Log (last 20 of $LINES entries) ==="
  tail -20 "$LOG"
fi
