#!/bin/bash
set -euo pipefail

# enforce-no-idle.sh
# TeammateIdle hook: phase-aware idle enforcement with checkpoint and advice checking.
#
# Phases (checked in priority order):
# 1. Retro pending: .retro-requested exists, .retro-{agent}.md missing → nudge retro
#    (takes priority over shutdown so agents can write retros before being stopped)
# 2. Shutdown: .shutdown exists → block on unresolved OBJECTIONs, then force-stop
# 3. Retro done: .retro-requested + .retro-{agent}.md exist, no .shutdown → allow idle
# 4. Phase 5 working state:
#    5a. Explicit waiting states (waiting_on_driver, waiting_on_verification) → allow
#    5b. Navigator drift (navigator, navigating phase) → require READY artifact
#    5d. Checkpoint check (driver with uncheckpointed edits) → block with checkpoint nudge
#    5e. Advice check (any agent with unresolved advice) → block with advice summary
#    5c. Generic working → nudge "go find work"
#
# No-op when no active popcorn-xp session.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/session-common.sh"
source "$SCRIPT_DIR/context-store-log.sh"
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

# Phase 5a: explicit waiting states (check navigator READY requirement first)
IN_WAITING_STATE=0
if [ "$PHASE" = "waiting_on_driver" ] || [ "$PHASE" = "waiting_on_verification" ]; then
  IN_WAITING_STATE=1
  # Navigator must have READY artifact published
  if [ "$ROLE" = "navigator" ] && { [ "$NAV_READY" != "true" ] || [ "$NAV_STATUS" != "published" ]; }; then
    KIND_LABEL="${NAV_KIND:-risk_check}"
    echo "Popcorn XP: Before you idle as navigator on task ${TASK_ID:-current}, publish your READY artifact (${KIND_LABEL}) and set state. Use: .popcorn-xp/$TEAM/session ready ${AGENT_SHORT:-agent} ${TASK_ID:-current} ${KIND_LABEL} 'What you checked and what the driver should watch.'" >&2
    exit 2
  fi
fi

# Phase 5b: navigator drift — require a concrete artifact
if [ "$ROLE" = "navigator" ] && [ "$PHASE" = "navigating" ]; then
  echo "Popcorn XP: Navigators do not go idle. Publish a READY artifact first (risk check, test plan, spec check, or review note), then either switch to waiting_on_driver or send concrete advice. Next action: ${NEXT_ACTION:-review the current driver task and publish what they should watch.}" >&2
  exit 2
fi

# Phase 5d: checkpoint check (driver with uncheckpointed edits)
if [ "$ROLE" = "driver" ] || [ "$PHASE" = "driving" ]; then
  LOG_FILE=$(cs_log_file)
  CURSOR_FILE=$(cs_checkpoint_cursor_file "$TEAM_DIR")
  COUNT=$(cs_edit_count_since_cursor "$LOG_FILE" "$CURSOR_FILE")
  if [ "$COUNT" -gt 0 ]; then
    echo "Popcorn XP: You have $COUNT file edit(s) since your last checkpoint. Send a checkpoint to your navigator and log it: .popcorn-xp/$TEAM/session log 'what you did'" >&2
    exit 2
  fi
fi

# Phase 5e: advice check (any agent with unresolved advice)
ADVICE="$TEAM_DIR/ADVICE.md"
if [ -f "$ADVICE" ]; then
  # Skip OBJECTION-specific check if in waiting_on_driver with no OBJECTIONs (they can wait for driver)
  if [ "$IN_WAITING_STATE" = "1" ] && [ "$PHASE" = "waiting_on_driver" ]; then
    open_obj_ids=$(grep -oE '### OBJECTION ([^ ]+) — open' "$ADVICE" | sed 's/### OBJECTION \([^ ]*\) — open/\1/' || true)
    if [ -z "$open_obj_ids" ]; then
      # No OBJECTIONs, waiting_on_driver can proceed to 5a exit
      :
    else
      # Has OBJECTIONs, must resolve
      total=0
      summary=""
      for TYPE in "OBJECTION" "SMELL" "STEER" "FYI"; do
        open_ids=$(grep -oE "### $TYPE ([^ ]+) — open" "$ADVICE" | sed 's/### [^ ]* \([^ ]*\) — open/\1/' || true)
        count=0
        for id in $open_ids; do
          if ! grep -iqE "^### $id — (FIXED|REJECTED|INCORPORATED|NOTED)" "$ADVICE"; then
            count=$((count + 1))
          fi
        done
        if [ "$count" -gt 0 ]; then
          total=$((total + count))
          [ -n "$summary" ] && summary="$summary, "
          summary="${summary}${count} ${TYPE}(s)"
        fi
      done

      if [ "$total" -gt 0 ]; then
        echo "Popcorn XP: ${total} unresolved advice item(s) in .popcorn-xp/$TEAM/ADVICE.md (${summary}). OBJECTIONs must be resolved before task completion. SMELLs, STEERs, and FYIs are your call — resolve if you can, but don't let them hold up good work." >&2
        exit 2
      fi
    fi
  else
    # Not in waiting_on_driver, check all advice items
    total=0
    summary=""
    for TYPE in "OBJECTION" "SMELL" "STEER" "FYI"; do
      open_ids=$(grep -oE "### $TYPE ([^ ]+) — open" "$ADVICE" | sed 's/### [^ ]* \([^ ]*\) — open/\1/' || true)
      count=0
      for id in $open_ids; do
        if ! grep -iqE "^### $id — (FIXED|REJECTED|INCORPORATED|NOTED)" "$ADVICE"; then
          count=$((count + 1))
        fi
      done
      if [ "$count" -gt 0 ]; then
        total=$((total + count))
        [ -n "$summary" ] && summary="$summary, "
        summary="${summary}${count} ${TYPE}(s)"
      fi
    done

    if [ "$total" -gt 0 ]; then
      echo "Popcorn XP: ${total} unresolved advice item(s) in .popcorn-xp/$TEAM/ADVICE.md (${summary}). OBJECTIONs must be resolved before task completion. SMELLs, STEERs, and FYIs are your call — resolve if you can, but don't let them hold up good work." >&2
      exit 2
    fi
  fi
fi

# Phase 5c: explicit waiting states allow idle (after advice/checkpoint checks pass)
if [ "$IN_WAITING_STATE" = "1" ]; then
  exit 0
fi

# Phase 5c2: completed tasks allow idle — agent is between tasks, waiting for assignment
if [ "$PHASE" = "completed" ]; then
  exit 0
fi

# Phase 5f: generic working state — no matching phase found
# Debounce: allow through after 3 consecutive nudges to prevent infinite block loops
NUDGE_FILE="$TEAM_DIR/.idle-nudge-${AGENT_SHORT}"
NUDGE_COUNT=0
if [ -f "$NUDGE_FILE" ]; then
  NUDGE_COUNT=$(cat "$NUDGE_FILE" 2>/dev/null || echo 0)
  [[ "$NUDGE_COUNT" =~ ^[0-9]+$ ]] || NUDGE_COUNT=0
fi
NUDGE_COUNT=$((NUDGE_COUNT + 1))
echo "$NUDGE_COUNT" > "$NUDGE_FILE"

if [ "$NUDGE_COUNT" -ge 3 ]; then
  rm -f "$NUDGE_FILE"
  exit 0
fi

DETAIL=""
[ -n "$NEXT_ACTION" ] && DETAIL=" Next action: $NEXT_ACTION."
[ -n "$BLOCKED_ON" ] && DETAIL="$DETAIL Blocked on: $BLOCKED_ON."
echo "Popcorn XP: Agents must never idle without a declared state. Set your phase and next action with .popcorn-xp/$TEAM/session state ${AGENT_SHORT:-agent} <role> <phase> <task-id> <blocked-on|-> <next action>, then either keep working or enter an explicit waiting state.$DETAIL" >&2
exit 2
