#!/bin/bash
set -euo pipefail

# check-task-claim.sh
# PreToolUse hook on TaskUpdate: enforces task claim rules.
#
# Blocks (exit 2) when a popcorn-xp agent:
#   1. Claims a task (status=in_progress or owner set) after .shutdown exists
#   2. Claims a new task while already owning another active task in agent-state
#
# No-op when no active popcorn-xp session or not a claim operation.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/session-common.sh"
px_load_session || exit 0

INPUT=$(cat)
STATUS=$(echo "$INPUT" | jq -r '.tool_input.status // empty' 2>/dev/null || true)
OWNER=$(echo "$INPUT" | jq -r '.tool_input.owner // empty' 2>/dev/null || true)
TASK_ID=$(echo "$INPUT" | jq -r '.tool_input.taskId // empty' 2>/dev/null || true)

# Only enforce on claim operations: status=in_progress OR owner being set
[ "$STATUS" != "in_progress" ] && [ -z "$OWNER" ] && exit 0

AGENT=$(px_normalize_agent "$(echo "$INPUT" | jq -r '.agent_type // empty' 2>/dev/null || true)")
px_is_teammate "$AGENT" || exit 0

AGENT_SHORT=$(px_short_agent "$AGENT")

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
   [ "$CURRENT_STATE_PHASE" != "completed" ]; then
  echo "Popcorn XP: You already have task ${CURRENT_STATE_TASK} in phase ${CURRENT_STATE_PHASE}. Complete it, hand it off, or set your state before claiming a new task." >&2
  exit 2
fi

exit 0
