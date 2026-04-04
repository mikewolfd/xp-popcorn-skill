#!/bin/bash
set -euo pipefail

# context-store-check.sh
# PreToolUse hook on Read: checks the shared context store.
# If the file has been read before, injects additionalContext
# with metadata (who read/edited, when, dirty status).
# Always allows the read to proceed (inform, not deny).
# No-op when no active popcorn-xp session.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/session-common.sh"
px_load_session || exit 0

STORE="$POPCORN_DIR/context-store.json"
[ ! -f "$STORE" ] && exit 0

source "$SCRIPT_DIR/context-store-log.sh"

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)
[ -z "$FILE_PATH" ] && exit 0

# Skip session bookkeeping files
case "$FILE_PATH" in
  */.popcorn-xp/*|.popcorn-xp/*) exit 0 ;;
esac

# Skip files outside the project directory
if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
  case "$FILE_PATH" in
    "${CLAUDE_PROJECT_DIR}"/*) ;;  # inside project — continue
    *) exit 0 ;;
  esac
fi

AGENT=$(px_normalize_agent "$(echo "$INPUT" | jq -r '.agent_type // empty' 2>/dev/null || true)")

# Read-only access, no lock needed
ENTRY=$(jq -r --arg path "$FILE_PATH" '.[$path] // empty' "$STORE" 2>/dev/null || true)
[ -z "$ENTRY" ] && exit 0

READ_BY=$(echo "$ENTRY" | jq -r '.read_by // empty')
READ_AT=$(echo "$ENTRY" | jq -r '.read_at // empty')
DIRTY=$(echo "$ENTRY" | jq -r '.dirty // false')
EDITED_BY=$(echo "$ENTRY" | jq -r '.edited_by // empty')
EDITED_AT=$(echo "$ENTRY" | jq -r '.edited_at // empty')

# Build context message
if [ -n "$READ_BY" ] && [ -n "$READ_AT" ]; then
  MSG="[context-store] File previously read by $READ_BY at $READ_AT."
else
  MSG="[context-store] File has not been read through the context store yet."
fi

if [ "$DIRTY" = "true" ]; then
  if [ -n "$EDITED_BY" ]; then
    MSG="$MSG Marked DIRTY — edited by $EDITED_BY at $EDITED_AT."
  else
    MSG="$MSG Marked DIRTY."
  fi
  cs_log "READ" "$AGENT" "$FILE_PATH" "cache hit, DIRTY by ${EDITED_BY:-unknown}"
else
  MSG="$MSG File is CLEAN (unchanged since last read)."
  cs_log "READ" "$AGENT" "$FILE_PATH" "cache hit, CLEAN, read by ${READ_BY:-unknown}"
fi

jq -n --arg ctx "$MSG" '{additionalContext: $ctx}'
exit 0
