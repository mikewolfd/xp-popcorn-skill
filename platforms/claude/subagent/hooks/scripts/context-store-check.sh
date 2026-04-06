#!/bin/bash
set -euo pipefail

# context-store-check.sh
# PreToolUse hook on Read: checks context-store.log for cross-agent edits.
# ONLY emits additionalContext when ALL of these are true:
# 1. Another agent has an EDIT event for this file in the log
# 2. Current agent is different from that editor
# Otherwise exits silently (exit 0, no output).
# No-op when no active popcorn-xp session.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../../.." && pwd)"
# shellcheck source=../../../../../shared/runtime/lib/session-common.sh
source "$REPO_ROOT/shared/runtime/lib/session-common.sh"
px_load_session || exit 0
px_is_subagent_mode && exit 0

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

# Derive state from log — no JSON store needed
STATE=$(cs_file_state "$FILE_PATH")
[ -z "$STATE" ] && exit 0

EDITED_BY=$(echo "$STATE" | awk '{print $1}')
EDITED_AT=$(echo "$STATE" | awk '{print $2}')

# Only emit context if current agent differs from last editor
if [ -n "$EDITED_BY" ] && [ "$EDITED_BY" != "$AGENT" ]; then
  MSG="[context-store] WARNING: $FILE_PATH was edited by $EDITED_BY at $EDITED_AT and has uncommitted changes. Coordinate with your teammate before making changes."
  cs_log "READ" "$AGENT" "$FILE_PATH" "cache hit, DIRTY by ${EDITED_BY}"
  jq -n --arg ctx "$MSG" '{additionalContext: $ctx}'
fi

exit 0
