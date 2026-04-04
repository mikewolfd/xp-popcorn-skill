#!/bin/bash
set -euo pipefail

# context-store-check.sh
# PreToolUse hook on Read: checks the shared context store.
# ONLY emits additionalContext when ALL of these are true:
# 1. File is marked dirty (dirty=true)
# 2. Current agent is different from the agent that edited it (edited_by != AGENT)
# Otherwise exits silently (exit 0, no output).
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

DIRTY=$(echo "$ENTRY" | jq -r '.dirty // false')
EDITED_BY=$(echo "$ENTRY" | jq -r '.edited_by // empty')
EDITED_AT=$(echo "$ENTRY" | jq -r '.edited_at // empty')

# Only emit context if BOTH conditions are true:
# 1. File is marked dirty
# 2. Current agent is different from editor (cross-agent dirty)
if [ "$DIRTY" = "true" ] && [ -n "$EDITED_BY" ] && [ "$EDITED_BY" != "$AGENT" ]; then
  MSG="[context-store] WARNING: $FILE_PATH was edited by $EDITED_BY at $EDITED_AT and has uncommitted changes. Coordinate with your teammate before making changes."
  cs_log "READ" "$AGENT" "$FILE_PATH" "cache hit, DIRTY by ${EDITED_BY}"
  jq -n --arg ctx "$MSG" '{additionalContext: $ctx}'
fi

exit 0
