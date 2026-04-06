#!/bin/bash
set -euo pipefail

# record-compact-summary.sh
# PostCompact hook: persists the compact summary and marks the teammate
# for retirement on its next idle cycle.
#
# Per hooks-ref.md, PostCompact has no decision control. This hook only writes
# follow-up state; enforce-no-idle.sh performs the actual stop later.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../../.." && pwd)"
# shellcheck source=../../../../../shared/runtime/lib/session-common.sh
source "$REPO_ROOT/shared/runtime/lib/session-common.sh"
px_load_session || exit 0

INPUT=$(cat)
AGENT=$(px_normalize_agent "$(echo "$INPUT" | jq -r '.agent_type // empty' 2>/dev/null || true)")
px_is_teammate "$AGENT" || exit 0

AGENT_SHORT=$(px_short_agent "$AGENT")
TRIGGER=$(echo "$INPUT" | jq -r '.trigger // "unknown"' 2>/dev/null || echo "unknown")
SUMMARY=$(echo "$INPUT" | jq -r '.compact_summary // ""' 2>/dev/null || true)
PENDING_FILE=$(px_compact_pending_file "$AGENT_SHORT")
STOP_FILE=$(px_compact_stop_file "$AGENT_SHORT")
SUMMARY_LOG="$TEAM_DIR/COMPACTIONS.md"

if [ -f "$PENDING_FILE" ]; then
  TASK_ID=$(jq -r '.state.task_id // empty' "$PENDING_FILE" 2>/dev/null || true)
  PHASE=$(jq -r '.state.phase // empty' "$PENDING_FILE" 2>/dev/null || true)
else
  TASK_ID=$(px_state_field "$AGENT_SHORT" "task_id")
  PHASE=$(px_state_field "$AGENT_SHORT" "phase")
fi

{
  printf '\n## Compact — %s\n' "$AGENT_SHORT"
  printf 'Trigger: %s\n' "$TRIGGER"
  printf 'Recorded: %s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  [ -n "$TASK_ID" ] && printf 'Task: %s\n' "$TASK_ID"
  [ -n "$PHASE" ] && printf 'Phase: %s\n' "$PHASE"
  printf '\n### Summary\n%s\n' "${SUMMARY:-"(empty compact summary)"}"
} >> "$SUMMARY_LOG"

jq -n \
  --arg agent "$AGENT_SHORT" \
  --arg trigger "$TRIGGER" \
  --arg task_id "$TASK_ID" \
  --arg phase "$PHASE" \
  --arg created_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
  --arg summary_log "$SUMMARY_LOG" \
  '{
    agent: $agent,
    trigger: $trigger,
    task_id: $task_id,
    phase: $phase,
    created_at: $created_at,
    summary_log: $summary_log
  }' > "$STOP_FILE"

rm -f "$PENDING_FILE"

exit 0
