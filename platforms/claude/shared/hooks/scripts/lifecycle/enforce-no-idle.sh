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
# 4. Compaction: compact-stop file exists → require handoff, then retire
#    4b. Bench: phase="bench" → allow idle (agent has no tasks)
# 5. Working state:
#    5a. Explicit waiting states (waiting_on_driver, waiting_on_verification) → allow
#    5b. Navigator drift (navigator, navigating phase) → require READY artifact
#    5d. Checkpoint check (driver with uncheckpointed edits) → team: context-store only
#    5e-adv. Advisor review → team: context-store; subagent: task chat vs .review-cursor-*
#    5e. Advice check (any agent with unresolved advice) → block with advice summary
#    5c. Generic working → nudge "go find work"
#
# Subagent mode: Phases 1–4 unchanged. Working-phase nudges skip context-store (5d/team 5e-adv).
# Navigators in waiting_on_driver must cursor-ack task chat (meta cursors) before idling.
# Unregistered agents (no agent-state file or empty role+phase) exit 0 — TeammateIdle is not the primary subagent transport.
#
# No-op when no active popcorn-xp session.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../../../.." && pwd)"
# shellcheck source=../../../../../../shared/runtime/lib/session-common.sh
source "$REPO_ROOT/shared/runtime/lib/session-common.sh"
source "$SCRIPT_DIR/../team/context-store-log.sh"
px_load_session || exit 0

SUBAGENT_MODE=0
px_is_subagent_mode && SUBAGENT_MODE=1

_px_task_slug() {
  local raw="${1:-}"
  raw="${raw#T}"
  raw="${raw#t}"
  printf 'T%s' "$raw"
}

# Local helper: emit advice block message and exit 2 if any unresolved items exist.
_px_advice_block() {
  local advice_path="${1:?}"
  local total=0 summary="" TYPE count
  while IFS=' ' read -r TYPE count; do
    [ -n "$TYPE" ] || continue
    total=$((total + count))
    [ -n "$summary" ] && summary="$summary, "
    summary="${summary}${count} ${TYPE}(s)"
  done < <(px_unresolved_advice "$advice_path")
  if [ "$total" -gt 0 ]; then
    echo "Popcorn XP: ${total} unresolved advice item(s) in .popcorn-xp/$TEAM/ADVICE.md (${summary}). OBJECTIONs must be resolved before task completion. SMELLs, STEERs, and FYIs are your call — resolve if you can, but don't let them hold up good work." >&2
    exit 2
  fi
}

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
if [ -f "$TEAM_DIR/.retro-requested" ] && [ -n "$AGENT_SHORT" ] && [ ! -f "$TEAM_DIR/.retro-$AGENT_SHORT.md" ]; then
  echo "Popcorn XP: Retro time. Submit your process observations now: .popcorn-xp/$TEAM/session retro $AGENT_SHORT 'What worked? What didn't? What would you change about the process?'" >&2
  exit 2
fi

# Phase 2: Shutdown — block on unresolved OBJECTIONs, then remind agent to approve shutdown_request
# Note: {"continue": false} does not reliably stop agents. The lead must send an explicit
# shutdown_request message to each teammate; agents approve it to terminate their session.
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
  px_update_state "$AGENT_SHORT" "$TASK_ID" \
    '.phase = "shutdown" | .next_action = "" | .blocked_on = ""'
  echo "Popcorn XP: Shutdown in progress. Approve the shutdown_request from the lead." >&2
  exit 2
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

# Phase 4b: bench — agent has no tasks, allow idle
if [ "$PHASE" = "bench" ]; then
  exit 0
fi

# Subagent: no registered state — do not apply teammate idle nudges (lead/subagent workers may idle harmlessly)
if [ "$SUBAGENT_MODE" -eq 1 ]; then
  if [ -z "$AGENT_SHORT" ]; then
    exit 0
  fi
  _state_path=$(px_state_file "$AGENT_SHORT")
  if [ ! -f "$_state_path" ] || { [ -z "$ROLE" ] && [ -z "$PHASE" ]; }; then
    exit 0
  fi
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
  # Subagent: navigator waiting on driver must catch up on task chat (per-agent line cursor in meta.json)
  if [ "$SUBAGENT_MODE" -eq 1 ] && [ "$ROLE" = "navigator" ] && [ "$PHASE" = "waiting_on_driver" ] && [ -n "$TASK_ID" ]; then
    _ts=$(_px_task_slug "$TASK_ID")
    _bf="$TEAM_DIR/tasks/$_ts/back-forth.md"
    _meta="$TEAM_DIR/tasks/$_ts/meta.json"
    if [ -f "$_bf" ] && [ -f "$_meta" ]; then
      _total=$(wc -l < "$_bf" | tr -d ' ')
      _cur=$(jq -r --arg a "$AGENT_SHORT" '(.cursors // {})[$a] // 0' "$_meta" 2>/dev/null || echo 0)
      [[ "$_cur" =~ ^[0-9]+$ ]] || _cur=0
      if [ "$_total" -gt "$_cur" ]; then
        echo "Popcorn XP (subagent): Task $_ts chat has lines not covered by your cursor ($_cur / $_total). Read .popcorn-xp/$TEAM/tasks/$_ts/back-forth.md and run: .popcorn-xp/$TEAM/session cursor-ack ${AGENT_SHORT:-agent} $_ts <last_line_seen>" >&2
        exit 2
      fi
    fi
  fi
fi

# Phase 5b: navigator drift — require a concrete artifact
if [ "$ROLE" = "navigator" ] && [ "$PHASE" = "navigating" ]; then
  echo "Popcorn XP: Navigators do not go idle. Publish a READY artifact first (risk check, test plan, spec check, or review note), then either switch to waiting_on_driver or send concrete advice. Next action: ${NEXT_ACTION:-review the current driver task and publish what they should watch.}" >&2
  exit 2
fi

# Phase 5d: checkpoint check (driver with uncheckpointed edits) — team / context-store only
if [ "$SUBAGENT_MODE" -eq 0 ]; then
  if [ "$ROLE" = "driver" ] || [ "$PHASE" = "driving" ]; then
    LOG_FILE=$(cs_log_file)
    CURSOR_FILE=$(cs_checkpoint_cursor_file "$TEAM_DIR")
    COUNT=$(cs_edit_count_since_cursor "$LOG_FILE" "$CURSOR_FILE")
    if [ "$COUNT" -gt 0 ]; then
      echo "Popcorn XP: You have $COUNT file edit(s) since your last checkpoint. Send a checkpoint to your navigator and log it: .popcorn-xp/$TEAM/session log 'what you did'" >&2
      exit 2
    fi
  fi
fi

# Phase 5e-adv: advisor review — team uses context-store; subagent uses task chat line count
if [ "$ROLE" = "advisor" ]; then
  if [ "$SUBAGENT_MODE" -eq 1 ] && [ -n "$TASK_ID" ]; then
    _ts=$(_px_task_slug "$TASK_ID")
    _bf="$TEAM_DIR/tasks/$_ts/back-forth.md"
    if [ -f "$_bf" ]; then
      _total=$(wc -l < "$_bf" | tr -d ' ')
      _rc=0
      if [ -f "$TEAM_DIR/.review-cursor-$AGENT_SHORT" ]; then
        _rraw=$(tr -d '[:space:]' < "$TEAM_DIR/.review-cursor-$AGENT_SHORT" || true)
        [[ "$_rraw" =~ ^[0-9]+$ ]] && _rc=$_rraw
      fi
      if [ "$_total" -gt "$_rc" ]; then
        echo "Popcorn XP (subagent): Task $_ts chat has lines not covered by your review cursor ($_rc / $_total). Read .popcorn-xp/$TEAM/tasks/$_ts/back-forth.md and run: .popcorn-xp/$TEAM/session review $AGENT_SHORT" >&2
        exit 2
      fi
    fi
  elif [ "$SUBAGENT_MODE" -eq 0 ]; then
    LOG_FILE=$(cs_log_file)
    REVIEW_CURSOR_FILE=$(cs_review_cursor_file "$TEAM_DIR" "$AGENT_SHORT")
    REVIEW_COUNT=$(cs_edit_count_since_review_cursor "$LOG_FILE" "$REVIEW_CURSOR_FILE")
    if [ "$REVIEW_COUNT" -gt 0 ]; then
      echo "Popcorn XP: $REVIEW_COUNT new edit(s) since your last review. Read .popcorn-xp/context-store.log, check the affected files, and advise. Log your review: .popcorn-xp/$TEAM/session review $AGENT_SHORT" >&2
      exit 2
    fi
  fi
fi

# Phase 5e: advice check (any agent with unresolved advice)
# waiting_on_driver: skip unless there are open OBJECTIONs (non-OBJECTIONs can wait for driver)
ADVICE="$TEAM_DIR/ADVICE.md"
if [ -f "$ADVICE" ]; then
  if [ "$IN_WAITING_STATE" = "1" ] && [ "$PHASE" = "waiting_on_driver" ]; then
    obj_count=$(px_unresolved_advice "$ADVICE" OBJECTION | awk '{print $2}')
    if [ -n "$obj_count" ] && [ "$obj_count" -gt 0 ]; then
      _px_advice_block "$ADVICE"
    fi
  else
    _px_advice_block "$ADVICE"
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
