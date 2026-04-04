#!/bin/bash
set -euo pipefail

# context-store-update-read.sh
# PostToolUse hook on Read: updates the shared context store
# with file metadata, agent name, timestamp, and read range.
# No-op when no active popcorn-xp session.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/session-common.sh"
px_load_session || exit 0

STORE="$POPCORN_DIR/context-store.json"

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
OFFSET=$(echo "$INPUT" | jq '.tool_input.offset // null' 2>/dev/null || echo "null")
LIMIT=$(echo "$INPUT" | jq '.tool_input.limit // null' 2>/dev/null || echo "null")
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Check if this is a new entry or an update
IS_NEW="true"
if [ -f "$STORE" ]; then
  HAS=$(jq -r --arg path "$FILE_PATH" 'has($path)' "$STORE" 2>/dev/null || echo "false")
  [ "$HAS" = "true" ] && IS_NEW="false"
fi

# Initialize store if it doesn't exist
[ ! -f "$STORE" ] && echo '{}' > "$STORE"

# Update in place while preserving prior edited_by / edited_at metadata
lockf "$STORE.lock" bash -c '
  jq \
    --arg path "$1" \
    --arg agent "$2" \
    --arg ts "$3" \
    --argjson offset "$4" \
    --argjson limit "$5" \
    '"'"'.[$path] = ((.[$path] // {}) + {read_by: $agent, read_at: $ts, offset: $offset, limit: $limit, dirty: false}) | .[$path] |= del(.preview)'"'"' \
    "$6" > "$6.tmp" && mv "$6.tmp" "$6"
' _ "$FILE_PATH" "$AGENT" "$TIMESTAMP" "$OFFSET" "$LIMIT" "$STORE"

# Log the event
if [ "$IS_NEW" = "true" ]; then
  cs_log "READ" "$AGENT" "$FILE_PATH" "new entry"
else
  cs_log "READ" "$AGENT" "$FILE_PATH" "updated"
fi

exit 0
