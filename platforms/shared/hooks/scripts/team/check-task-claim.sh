#!/bin/bash
set -euo pipefail

# check-task-claim.sh
# PreToolUse hook on TaskUpdate: enforces task claim rules.
#
# Blocks (exit 2) when a popcorn-xp agent:
#   1. Claims a task (status=in_progress or owner set) after .shutdown exists
#   2. Claims a new task while already owning another active task in agent-state
#   3. (V52) Drives back-to-back — same agent drove the immediately prior session task
#
# No-op when no active popcorn-xp session or not a claim operation.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../../.." && pwd)"
# shellcheck source=../../../../shared/runtime/lib/session-common.sh
source "$REPO_ROOT/shared/runtime/lib/session-common.sh"
px_load_session || exit 0
px_is_subagent_mode && exit 0

INPUT=$(cat)
STATUS=$(echo "$INPUT" | jq -r '.tool_input.status // empty' 2>/dev/null || true)
OWNER=$(echo "$INPUT" | jq -r '.tool_input.owner // empty' 2>/dev/null || true)
TASK_ID=$(echo "$INPUT" | jq -r '.tool_input.taskId // empty' 2>/dev/null || true)
TASK_DESC=$(echo "$INPUT" | jq -r '.tool_input.description // .tool_input.task_subject // .tool_input.subject // .tool_input.title // empty' 2>/dev/null || true)

# Only enforce on claim operations: status=in_progress OR owner being set
[ "$STATUS" != "in_progress" ] && [ -z "$OWNER" ] && exit 0

AGENT=$(px_normalize_agent "$(echo "$INPUT" | jq -r '.agent_type // empty' 2>/dev/null || true)")
px_is_teammate "$AGENT" || exit 0

AGENT_SHORT=$(px_short_agent "$AGENT")
IS_CLAIM=0
if [ "$STATUS" = "in_progress" ] || [ -n "$OWNER" ]; then
  IS_CLAIM=1
fi
IS_NAV_TASK=0
px_is_nav_task "$TASK_ID" "$TASK_DESC" && IS_NAV_TASK=1

# 1. Shutdown guard
if [ -f "$TEAM_DIR/.shutdown" ]; then
  echo "Popcorn XP: Session is shutting down. You cannot claim new tasks after shutdown has been signalled. Write your retro if requested, then wait for the lead to issue TeamDelete." >&2
  exit 2
fi

# 2. Concurrent task guard via explicit agent state
CURRENT_STATE_TASK=$(px_state_field "$AGENT_SHORT" "task_id")
CURRENT_STATE_PHASE=$(px_state_field "$AGENT_SHORT" "phase")

if [ -n "$CURRENT_STATE_TASK" ] && [ "$CURRENT_STATE_TASK" != "$TASK_ID" ] && \
   [ "$CURRENT_STATE_PHASE" != "handoff_pending" ] && [ "$CURRENT_STATE_PHASE" != "idle" ] && \
   [ "$CURRENT_STATE_PHASE" != "completed" ] && [ "$CURRENT_STATE_PHASE" != "bench" ]; then
  echo "Popcorn XP: You already have task ${CURRENT_STATE_TASK} in phase ${CURRENT_STATE_PHASE}. Complete it, hand it off, or set your state before claiming a new task." >&2
  exit 2
fi

LOG_FILE="$TEAM_DIR/LOG.md"

# 3. V52/V70: Rotation guard — block consecutive driving by same agent, but allow nav task claims.
if [ "$IS_CLAIM" -eq 1 ] && [ "$IS_NAV_TASK" -eq 0 ] && [ -f "$LOG_FILE" ] && [ -d "$STATE_DIR" ]; then
  # Only enforce when 2+ teammate state files exist (single-agent teams exempt)
  teammate_count=$(find "$STATE_DIR" -name '*.json' -maxdepth 1 2>/dev/null | wc -l | tr -d ' ')
  if [ "$teammate_count" -ge 2 ]; then
    if grep -q "^## Task" "$LOG_FILE"; then
      last_driver=$(px_last_task_log_driver "$LOG_FILE")
      if [ -n "$last_driver" ] && [ "$last_driver" = "$AGENT_SHORT" ]; then
        echo "Popcorn XP: Rotation required. You (@$AGENT_SHORT) drove the last task. Another teammate must drive next to maintain rotation." >&2
        exit 2
      fi
    fi
  fi
fi

exit 0
