#!/bin/bash
set -euo pipefail

# SubagentStop hook: OBJECTION gate (same as TaskCompleted) when mode is subagent,
# plus optional additionalContext for open SMELL/STEER/FYI and compaction-pending.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
# shellcheck source=../../../runtime/lib/session-common.sh
source "$REPO_ROOT/shared/runtime/lib/session-common.sh"

INPUT=$(cat || true)
echo "$INPUT" | jq -e '.hook_event_name == "SubagentStop"' >/dev/null 2>&1 || exit 0

px_load_session || exit 0
px_is_subagent_mode || exit 0

tmp_out=$(mktemp)
tmp_err=$(mktemp)
set +e
bash "$SCRIPT_DIR/check-advice-on-complete.sh" < /dev/null >"$tmp_out" 2>"$tmp_err"
rc=$?
set -e
if [ "$rc" -eq 2 ]; then
  cat "$tmp_err" >&2
  rm -f "$tmp_out" "$tmp_err"
  exit 2
fi
warn_from_complete=""
if [ -s "$tmp_out" ]; then
  warn_from_complete=$(jq -r '.additionalContext // empty' "$tmp_out" 2>/dev/null || true)
fi
rm -f "$tmp_out" "$tmp_err"

AGENT_TYPE=$(echo "$INPUT" | jq -r '.agent_type // empty' 2>/dev/null || true)
SHORT=$(px_short_agent "$(px_normalize_agent "$AGENT_TYPE")")
compact_msg=""
if [ -n "$SHORT" ]; then
  cpfile=$(px_compact_pending_file "$SHORT")
  if [ -f "$cpfile" ]; then
    compact_msg="Compaction pending (.compact-pending-${SHORT}.json). Complete PostCompact / handoff before stopping if you were mid-work."
  fi
fi

if [ -n "$warn_from_complete" ] || [ -n "$compact_msg" ]; then
  jq -nc \
    --arg a "$warn_from_complete" \
    --arg b "$compact_msg" \
    '{additionalContext: (
      if ($a != "" and $b != "") then ($a + " " + $b)
      elif ($a != "") then $a
      else $b end
    )}'
fi

exit 0
