#!/bin/bash
set -euo pipefail

# context-store-mark-dirty.sh
# PreToolUse hook on Edit/Write: records every in-project edit as
# an event, updates the context store, and reminds drivers to checkpoint
# after 3+ edits since the last session log cursor.
# Soft lock: if another agent is already editing this file
# (dirty + different agent), injects additionalContext warning.
# Always allows the edit to proceed.
# No-op when no active popcorn-xp session.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/session-common.sh"
px_load_session || exit 0

STORE="$POPCORN_DIR/context-store.json"
[ ! -f "$STORE" ] && echo '{}' > "$STORE"

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
AGENT_SHORT=$(px_short_agent "$AGENT")
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
LOG_FILE=$(cs_log_file)
CURSOR_FILE=$(cs_checkpoint_cursor_file "$TEAM_DIR")

if [ "$AGENT" != "lead" ] && [ "$AGENT" != "unknown" ] && px_has_write_set "$AGENT_SHORT" && ! px_path_in_write_set "$AGENT_SHORT" "$FILE_PATH"; then
  echo "Popcorn XP: $AGENT_SHORT is editing outside the declared write set for task $(px_state_field "$AGENT_SHORT" "task_id"). File: $FILE_PATH. Update the task write set or hand the task off before editing this file." >&2
  exit 2
fi

# Read existing entry in one jq call
ENTRY_JSON=$(jq -r --arg path "$FILE_PATH" \
  'if has($path) then .[$path] | "\(.dirty // false)\t\(.edited_by // "")\t\(.edited_at // "")" else "MISSING" end' \
  "$STORE" 2>/dev/null || echo "MISSING")

EXISTING_DIRTY="false"
EXISTING_EDITOR=""
EXISTING_EDITED_AT=""
if [ "$ENTRY_JSON" != "MISSING" ]; then
  EXISTING_DIRTY=$(echo "$ENTRY_JSON" | cut -f1)
  EXISTING_EDITOR=$(echo "$ENTRY_JSON" | cut -f2)
  EXISTING_EDITED_AT=$(echo "$ENTRY_JSON" | cut -f3)
fi

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
    ".[\$path] = ((.[\$path] // {}) + {dirty: true, edited_by: \$agent, edited_at: \$ts})" \
    "$4" > "$4.tmp" && mv "$4.tmp" "$4"
' _ "$FILE_PATH" "$AGENT" "$TIMESTAMP" "$STORE"

# Emit soft lock warning and/or checkpoint reminder
EDIT_COUNT=$(cs_edit_count_since_cursor "$LOG_FILE" "$CURSOR_FILE")
CHECKPOINT_MSG=""
if [ "$EDIT_COUNT" -ge 3 ]; then
  CHECKPOINT_MSG="Popcorn XP: You have $EDIT_COUNT file edits since your last checkpoint. Send a checkpoint to your navigator and log it: .popcorn-xp/$TEAM/session log 'what you did'"
fi

if [ -n "$SOFT_LOCK_MSG" ] || [ -n "$CHECKPOINT_MSG" ]; then
  CTX="$SOFT_LOCK_MSG"
  if [ -n "$CTX" ] && [ -n "$CHECKPOINT_MSG" ]; then
    CTX="$CTX"$'\n\n'"$CHECKPOINT_MSG"
  elif [ -z "$CTX" ]; then
    CTX="$CHECKPOINT_MSG"
  fi
  jq -n --arg ctx "$CTX" '{additionalContext: $ctx}'
fi

exit 0
