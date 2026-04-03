#!/bin/bash
set -euo pipefail

# context-store-update-read.sh
# PostToolUse hook on Read: updates the shared context store
# with file metadata, agent name, timestamp, read range,
# and the full file content as preview.
# No-op when no active popcorn-xp session.

POPCORN_DIR="${CLAUDE_PROJECT_DIR:-.}/.popcorn-xp"
TEAM=$(cat "$POPCORN_DIR/.active-team" 2>/dev/null || true)
[ -z "$TEAM" ] && exit 0
[ ! -d "$POPCORN_DIR/$TEAM" ] && exit 0

STORE="$POPCORN_DIR/context-store.json"

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
OFFSET=$(echo "$INPUT" | jq '.tool_input.offset // null' 2>/dev/null || echo "null")
LIMIT=$(echo "$INPUT" | jq '.tool_input.limit // null' 2>/dev/null || echo "null")
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Check if this is a new entry or an update
IS_NEW="true"
if [ -f "$STORE" ]; then
  HAS=$(jq -r --arg path "$FILE_PATH" 'has($path)' "$STORE" 2>/dev/null || echo "false")
  [ "$HAS" = "true" ] && IS_NEW="false"
fi

# Extract tool_response as preview — write to temp file to avoid quoting issues
PREVIEW_FILE=$(mktemp)
trap 'rm -f "$PREVIEW_FILE" "$PREVIEW_FILE.entry"' EXIT
echo "$INPUT" | jq -r '.tool_response // ""' > "$PREVIEW_FILE" 2>/dev/null || true

# Initialize store if it doesn't exist
[ ! -f "$STORE" ] && echo '{}' > "$STORE"

# Build the new entry as a JSON file, then merge into store
# This avoids passing file content through shell arguments
jq -n \
  --arg path "$FILE_PATH" \
  --arg agent "$AGENT" \
  --arg ts "$TIMESTAMP" \
  --argjson offset "$OFFSET" \
  --argjson limit "$LIMIT" \
  --rawfile preview "$PREVIEW_FILE" \
  '{($path): {read_by: $agent, read_at: $ts, offset: $offset, limit: $limit, dirty: false, preview: $preview}}' \
  > "$PREVIEW_FILE.entry"

# Merge: read current store, deep-merge new entry, write atomically
# lockf provides mutual exclusion on macOS — pass paths as positional args
lockf "$STORE.lock" bash -c '
  jq -s ".[0] * .[1]" "$1" "$2" > "$1.tmp" && mv "$1.tmp" "$1"
' _ "$STORE" "$PREVIEW_FILE.entry"

# Log the event
if [ "$IS_NEW" = "true" ]; then
  cs_log "READ" "$AGENT" "$FILE_PATH" "new entry"
else
  cs_log "READ" "$AGENT" "$FILE_PATH" "updated"
fi

exit 0
