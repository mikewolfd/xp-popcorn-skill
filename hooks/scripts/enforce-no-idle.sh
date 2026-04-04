#!/bin/bash
set -euo pipefail

# enforce-no-idle.sh
# TeammateIdle hook: phase-aware idle enforcement.
#
# Phases (checked in priority order):
# 1. Retro pending: .retro-requested exists, .retro-{agent}.md missing → nudge retro
#    (takes priority over shutdown so agents can write retros before being stopped)
# 2. Shutdown: .shutdown exists → block on unresolved OBJECTIONs, then force-stop
# 3. Retro done: .retro-requested + .retro-{agent}.md exist, no .shutdown → allow idle
# 4. Working: default → nudge "go find work"
#
# No-op when no active popcorn-xp session.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/session-common.sh"
px_load_session || exit 0

# Read teammate_name from stdin (TeammateIdle input)
INPUT=$(cat)
AGENT=$(echo "$INPUT" | jq -r '.teammate_name // empty' 2>/dev/null || true)
AGENT_SHORT=$(px_short_agent "$(px_normalize_agent "$AGENT")")
STATE=$(px_state_json "$AGENT_SHORT")
PHASE=$(echo "$STATE" | jq -r '.phase // empty' 2>/dev/null || true)
TASK_ID=$(echo "$STATE" | jq -r '.task_id // empty' 2>/dev/null || true)
ROLE=$(echo "$STATE" | jq -r '.role // empty' 2>/dev/null || true)
NEXT_ACTION=$(echo "$STATE" | jq -r '.next_action // empty' 2>/dev/null || true)
BLOCKED_ON=$(echo "$STATE" | jq -r '.blocked_on // empty' 2>/dev/null || true)
NAV_READY=$(echo "$STATE" | jq -r '.navigator_ready // false' 2>/dev/null || echo false)
NAV_KIND=$(echo "$STATE" | jq -r '.navigator_artifact_kind // empty' 2>/dev/null || true)
NAV_STATUS=$(echo "$STATE" | jq -r '.navigator_artifact_status // empty' 2>/dev/null || true)
COMPACT_STOP_FILE=$(px_compact_stop_file "$AGENT_SHORT")
HANDOFF_FILE="$TEAM_DIR/handoff-$AGENT_SHORT.md"

# Phase 1: Retro pending — nudge retro before shutdown can take effect
if [ -f "$TEAM_DIR/.retro-requested" ] && [ -n "$AGENT" ] && [ ! -f "$TEAM_DIR/.retro-$AGENT.md" ]; then
  echo "Popcorn XP: Retro time. Submit your process observations now: .popcorn-xp/$TEAM/session retro $AGENT 'What worked? What didn't? What would you change about the process?'" >&2
  exit 2
fi

# Phase 2: Shutdown — block on unresolved OBJECTIONs, then force-stop
if [ -f "$TEAM_DIR/.shutdown" ]; then
  ADVICE="$TEAM_DIR/ADVICE.md"
  if [ -f "$ADVICE" ]; then
    open_obj_ids=$(grep -oE '### OBJECTION ([^ ]+) — open' "$ADVICE" | sed 's/### OBJECTION \([^ ]*\) — open/\1/' || true)
    for id in $open_obj_ids; do
      if ! grep -iqE "^### $id — (FIXED|REJECTED|INCORPORATED|NOTED)" "$ADVICE"; then
        echo "Popcorn XP: Unresolved OBJECTION $id exists. Resolve all OBJECTIONs before shutdown — fix the issue or reject with reasoning: .popcorn-xp/$TEAM/session resolve $id REJECTED 'reason'" >&2
        exit 2
      fi
    done
  fi
  echo '{"continue": false, "stopReason": "Session complete — lead initiated shutdown"}'
  exit 0
fi

# Phase 3: Retro submitted, no shutdown yet — allow idle
if [ -f "$TEAM_DIR/.retro-requested" ]; then
  exit 0
fi

# Phase 4: teammate compacted — require handoff, then retire on next idle
if [ -f "$COMPACT_STOP_FILE" ]; then
  if [ ! -f "$HANDOFF_FILE" ]; then
    echo "Popcorn XP: Your context compacted. Before idling, write a handoff and message the lead or next driver so the session can continue with a fresh teammate: .popcorn-xp/$TEAM/session handoff ${AGENT_SHORT:-agent}" >&2
    exit 2
  fi
  rm -f "$COMPACT_STOP_FILE"
  echo '{"continue": false, "stopReason": "Context compacted — handoff captured; continue with a fresh teammate if more work is needed"}'
  exit 0
fi

# Phase 5a: explicit waiting states are allowed
if [ "$PHASE" = "waiting_on_driver" ] || [ "$PHASE" = "waiting_on_verification" ]; then
  if [ "$ROLE" = "navigator" ] && { [ "$NAV_READY" != "true" ] || [ "$NAV_STATUS" != "published" ]; }; then
    KIND_LABEL="${NAV_KIND:-risk_check}"
    echo "Popcorn XP: Before you idle as navigator on task ${TASK_ID:-current}, publish your READY artifact (${KIND_LABEL}) and set state. Use: .popcorn-xp/$TEAM/session ready ${AGENT_SHORT:-agent} ${TASK_ID:-current} ${KIND_LABEL} 'What you checked and what the driver should watch.'" >&2
    exit 2
  fi
  exit 0
fi

# Phase 5b: navigator drift — require a concrete artifact
if [ "$ROLE" = "navigator" ] && [ "$PHASE" = "navigating" ]; then
  echo "Popcorn XP: Navigators do not go idle. Publish a READY artifact first (risk check, test plan, spec check, or review note), then either switch to waiting_on_driver or send concrete advice. Next action: ${NEXT_ACTION:-review the current driver task and publish what they should watch.}" >&2
  exit 2
fi

# Phase 5c: generic working state
DETAIL=""
[ -n "$NEXT_ACTION" ] && DETAIL=" Next action: $NEXT_ACTION."
[ -n "$BLOCKED_ON" ] && DETAIL="$DETAIL Blocked on: $BLOCKED_ON."
echo "Popcorn XP: Agents must never idle without a declared state. Set your phase and next action with .popcorn-xp/$TEAM/session state ${AGENT_SHORT:-agent} <role> <phase> <task-id> <blocked-on|-> <next action>, then either keep working or enter an explicit waiting state.$DETAIL" >&2
exit 2
