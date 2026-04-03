#!/bin/bash
set -euo pipefail

# context-store-check.sh
# PreToolUse hook on Read: checks the shared context store.
# If the file has been read before, injects additionalContext
# with metadata (who read/edited, when, dirty status).
# Always allows the read to proceed (inform, not deny).
# No-op when no active popcorn-xp session.

POPCORN_DIR="${CLAUDE_PROJECT_DIR:-.}/.popcorn-xp"
TEAM=$(cat "$POPCORN_DIR/.active-team" 2>/dev/null || true)
[ -z "$TEAM" ] && exit 0
[ ! -d "$POPCORN_DIR/$TEAM" ] && exit 0

STORE="$POPCORN_DIR/context-store.json"
[ ! -f "$STORE" ] && exit 0

# Source the logger
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/context-store-log.sh"

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)
[ -z "$FILE_PATH" ] && exit 0

# Skip session bookkeeping files
case "$FILE_PATH" in
  */.popcorn-xp/*|.popcorn-xp/*) exit 0 ;;
esac

AGENT=$(echo "$INPUT" | jq -r '.agent_type // "unknown"' 2>/dev/null || echo "unknown")
# Prefix agent names with popcorn-xp: convention
if [ "$AGENT" != "unknown" ] && ! [[ "$AGENT" =~ ^popcorn-xp: ]]; then
  AGENT="popcorn-xp:$AGENT"
fi

# Read-only access, no lock needed
ENTRY=$(jq -r --arg path "$FILE_PATH" '.[$path] // empty' "$STORE" 2>/dev/null || true)
[ -z "$ENTRY" ] && exit 0

READ_BY=$(echo "$ENTRY" | jq -r '.read_by // "unknown"')
READ_AT=$(echo "$ENTRY" | jq -r '.read_at // "unknown"')
DIRTY=$(echo "$ENTRY" | jq -r '.dirty // false')
EDITED_BY=$(echo "$ENTRY" | jq -r '.edited_by // empty')
EDITED_AT=$(echo "$ENTRY" | jq -r '.edited_at // empty')

# Build context message
MSG="[context-store] File previously read by $READ_BY at $READ_AT."

if [ "$DIRTY" = "true" ]; then
  if [ -n "$EDITED_BY" ]; then
    MSG="$MSG Marked DIRTY — edited by $EDITED_BY at $EDITED_AT since last read."
  else
    MSG="$MSG Marked DIRTY since last read."
  fi
  cs_log "READ" "$AGENT" "$FILE_PATH" "cache hit, DIRTY by ${EDITED_BY:-unknown}"
else
  MSG="$MSG File is CLEAN (unchanged since last read)."
  cs_log "READ" "$AGENT" "$FILE_PATH" "cache hit, CLEAN, read by $READ_BY"
fi

jq -n --arg ctx "$MSG" '{additionalContext: $ctx}'
exit 0
