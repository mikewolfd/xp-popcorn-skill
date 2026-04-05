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
AGENT_SHORT=$(px_short_agent "$AGENT")
LOG_FILE=$(cs_log_file)
CURSOR_FILE=$(cs_checkpoint_cursor_file "$TEAM_DIR")

if [ "$AGENT" != "lead" ] && [ "$AGENT" != "unknown" ] && px_has_write_set "$AGENT_SHORT" && ! px_path_in_write_set "$AGENT_SHORT" "$FILE_PATH"; then
  echo "Popcorn XP: $AGENT_SHORT is editing outside the declared write set for task $(px_state_field "$AGENT_SHORT" "task_id"). File: $FILE_PATH. Update the task write set or hand the task off before editing this file." >&2
  exit 2
fi

# Role guard: navigators and advisors must not edit code files — send advice instead.
# Fail open: lead/unknown agents have no role state and are always allowed.
if [ "$AGENT" != "lead" ] && [ "$AGENT" != "unknown" ]; then
  AGENT_ROLE=$(px_state_field "$AGENT_SHORT" "role")
  if [ "$AGENT_ROLE" = "navigator" ] || [ "$AGENT_ROLE" = "advisor" ]; then
    echo "Popcorn XP: $AGENT_SHORT is $AGENT_ROLE, not driver. Send advice via SendMessage instead of editing directly. If you need to drive, claim a drive task first." >&2
    exit 2
  fi
fi

# One-driver-at-a-time guard: block if another agent is already in phase=driving.
# Only applies when the editing agent is also driving.
# V61: If the other driver's state is stale (>10 min), downgrade hard block to warning.
AGENT_PHASE=$(px_state_field "$AGENT_SHORT" "phase")
STALE_DRIVER_MSG=""
if [ "$AGENT" != "lead" ] && [ "$AGENT" != "unknown" ] && [ "$AGENT_PHASE" = "driving" ] && [ -d "$STATE_DIR" ]; then
  for state_file in "$STATE_DIR"/*.json; do
    [ -f "$state_file" ] || continue
    other_agent=$(jq -r '.agent // empty' "$state_file" 2>/dev/null || true)
    [ -z "$other_agent" ] && continue
    [ "$other_agent" = "$AGENT_SHORT" ] && continue
    other_phase=$(jq -r '.phase // empty' "$state_file" 2>/dev/null || true)
    if [ "$other_phase" = "driving" ]; then
      other_updated_at=$(jq -r '.updated_at // empty' "$state_file" 2>/dev/null || true)
      age=0
      if [ -n "$other_updated_at" ]; then
        now_epoch=$(date -u +%s)
        updated_epoch=$(date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$other_updated_at" +%s 2>/dev/null || true)
        # If parsing fails, treat as fresh (age=0) — conservative: keep hard block
        if [ -n "$updated_epoch" ] && [ "$updated_epoch" -gt 0 ] 2>/dev/null; then
          age=$((now_epoch - updated_epoch))
        fi
      fi
      if [ "$age" -gt 600 ]; then
        STALE_DRIVER_MSG="${STALE_DRIVER_MSG:+$STALE_DRIVER_MSG$'\n\n'}Popcorn XP: ⚠ $other_agent appears to be driving but their state is $((age / 60)) min old (possible crash). Proceeding cautiously — verify with the lead."
      else
        echo "Popcorn XP: $other_agent is already driving. Only one agent may drive at a time. Wait for $other_agent to complete or hand off before editing." >&2
        exit 2
      fi
    fi
  done
fi

# Derive last editor from log — no JSON store needed
EXISTING_STATE=$(cs_file_state "$FILE_PATH")
EXISTING_EDITOR=$(echo "$EXISTING_STATE" | awk '{print $1}')
EXISTING_EDITED_AT=$(echo "$EXISTING_STATE" | awk '{print $2}')

SOFT_LOCK_MSG=""
if [ -n "$EXISTING_EDITOR" ] && [ "$EXISTING_EDITOR" != "$AGENT" ]; then
  SOFT_LOCK_MSG="⚠ SOFT LOCK: $EXISTING_EDITOR is actively editing this file (since $EXISTING_EDITED_AT). Consider messaging them about your intended changes instead of editing directly to avoid conflicts."
  cs_log "EDIT" "$AGENT" "$FILE_PATH" "SOFT LOCK — $EXISTING_EDITOR active"
else
  cs_log "EDIT" "$AGENT" "$FILE_PATH" "marked dirty"
fi

# Emit soft lock warning and/or checkpoint reminder
EDIT_COUNT=$(cs_edit_count_since_cursor "$LOG_FILE" "$CURSOR_FILE")
CHECKPOINT_MSG=""
if [ "$EDIT_COUNT" -ge 3 ]; then
  CHECKPOINT_MSG="Popcorn XP: You have $EDIT_COUNT file edits since your last checkpoint. Send a checkpoint to your navigator and log it: .popcorn-xp/$TEAM/session log 'what you did'"
fi

if [ -n "$STALE_DRIVER_MSG" ] || [ -n "$SOFT_LOCK_MSG" ] || [ -n "$CHECKPOINT_MSG" ]; then
  CTX=""
  for msg in "$STALE_DRIVER_MSG" "$SOFT_LOCK_MSG" "$CHECKPOINT_MSG"; do
    [ -z "$msg" ] && continue
    if [ -z "$CTX" ]; then CTX="$msg"; else CTX="$CTX"$'\n\n'"$msg"; fi
  done
  jq -n --arg ctx "$CTX" '{additionalContext: $ctx}'
fi

exit 0
