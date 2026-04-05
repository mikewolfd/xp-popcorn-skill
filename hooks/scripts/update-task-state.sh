#!/bin/bash
set -euo pipefail

# update-task-registry.sh
# PostToolUse hook on TaskUpdate: maintains explicit agent-state for task claims.
#
# No-op when no active popcorn-xp session or not a claim/status change.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/session-common.sh"
px_load_session || exit 0

INPUT=$(cat)
STATUS=$(echo "$INPUT" | jq -r '.tool_input.status // empty' 2>/dev/null || true)
OWNER=$(echo "$INPUT" | jq -r '.tool_input.owner // empty' 2>/dev/null || true)
TASK_ID=$(echo "$INPUT" | jq -r '.tool_input.taskId // empty' 2>/dev/null || true)
AGENT=$(px_normalize_agent "$(echo "$INPUT" | jq -r '.agent_type // empty' 2>/dev/null || true)")

# Only track teammates
px_is_teammate "$AGENT" || exit 0

# Only act on claim operations or terminal status changes
[ -z "$STATUS" ] && [ -z "$OWNER" ] && exit 0
[ -z "$TASK_ID" ] && exit 0

AGENT_SHORT=$(px_short_agent "$AGENT")
mkdir -p "$STATE_DIR"
LOG_FILE="$TEAM_DIR/LOG.md"

if [ "$STATUS" = "in_progress" ] || { [ -n "$OWNER" ] && [ -z "$STATUS" ]; }; then
  PHASE="driving"
  NEXT_ACTION="Drive the claimed task and send a checkpoint after meaningful edits."
  if [ -z "$STATUS" ]; then
    PHASE="claimed"
    NEXT_ACTION="Start the claimed task or hand it off before claiming another."
  fi

  # V68: Only update state if the agent already has a state file (registered via session state).
  # Skip unknown/external agents that never registered with this session.
  if [ ! -f "$(px_state_file "$AGENT_SHORT")" ]; then
    exit 0
  fi

  px_update_state "$AGENT_SHORT" "$TASK_ID" \
    --arg agent "$AGENT_SHORT" \
    --arg task_id "$TASK_ID" \
    --arg role "driver" \
    --arg phase "$PHASE" \
    --arg next_action "$NEXT_ACTION" \
    '.agent = $agent
     | .task_id = $task_id
     | .role = $role
     | .phase = $phase
     | .blocked_on = ""
     | .next_action = $next_action'

  # Seed a fallback task anchor when this task skipped `session task`.
  # Older task headers do not help the rotation guard for the current claim.
  if [ ! -f "$LOG_FILE" ] || ! grep -qF "## Task $TASK_ID " "$LOG_FILE"; then
    printf '\n## Task %s (auto) — Driver @%s, Navigator @unknown\n' "$TASK_ID" "$AGENT_SHORT" >> "$LOG_FILE"
  fi
elif [ "$STATUS" = "completed" ] || [ "$STATUS" = "deleted" ]; then
  if [ -f "$(px_state_file "$AGENT_SHORT")" ]; then
    px_update_state "$AGENT_SHORT" "" \
      '.phase = "completed"
       | .role = "navigator"
       | .blocked_on = ""
       | .next_action = "Read the latest snapshot and advise the next driver."
       | .navigator_ready = false
       | .navigator_artifact_kind = ""
       | .navigator_artifact_status = ""
       | .write_set = []'
  fi
fi

exit 0
