#!/bin/bash
set -euo pipefail

# context-store-mark-dirty.sh
# PreToolUse hook on Edit/Write: marks the file as dirty
# in the context store and records who edited it.
# Soft lock: if another agent is already editing this file
# (dirty + different agent), injects additionalContext warning.
# Always allows the edit to proceed.
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
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Read existing entry in one jq call — exit if file not in store
ENTRY_JSON=$(jq -r --arg path "$FILE_PATH" \
  'if has($path) then .[$path] | "\(.dirty // false)\t\(.edited_by // "")\t\(.edited_at // "")" else "MISSING" end' \
  "$STORE" 2>/dev/null || echo "MISSING")
[ "$ENTRY_JSON" = "MISSING" ] && exit 0

EXISTING_DIRTY=$(echo "$ENTRY_JSON" | cut -f1)
EXISTING_EDITOR=$(echo "$ENTRY_JSON" | cut -f2)
EXISTING_EDITED_AT=$(echo "$ENTRY_JSON" | cut -f3)

SOFT_LOCK_MSG=""
if [ "$EXISTING_DIRTY" = "true" ] && [ -n "$EXISTING_EDITOR" ] && [ "$EXISTING_EDITOR" != "$AGENT" ]; then
  SOFT_LOCK_MSG="[context-store] SOFT LOCK: $EXISTING_EDITOR is actively editing this file (since $EXISTING_EDITED_AT). Consider messaging them about your intended changes instead of editing directly to avoid conflicts."
  cs_log "EDIT" "$AGENT" "$FILE_PATH" "SOFT LOCK — $EXISTING_EDITOR active"
else
  cs_log "EDIT" "$AGENT" "$FILE_PATH" "marked dirty"
fi

# Mark dirty atomically — pass all values as positional args to avoid quoting issues
lockf "$STORE.lock" bash -c '
  jq --arg path "$1" --arg agent "$2" --arg ts "$3" \
    ".[\$path].dirty = true | .[\$path].edited_by = \$agent | .[\$path].edited_at = \$ts" \
    "$4" > "$4.tmp" && mv "$4.tmp" "$4"
' _ "$FILE_PATH" "$AGENT" "$TIMESTAMP" "$STORE"

# Emit soft lock warning if another agent was editing
if [ -n "$SOFT_LOCK_MSG" ]; then
  jq -n --arg ctx "$SOFT_LOCK_MSG" '{additionalContext: $ctx}'
fi

exit 0
