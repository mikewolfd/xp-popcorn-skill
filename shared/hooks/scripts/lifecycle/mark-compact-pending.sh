#!/bin/bash
set -euo pipefail

# mark-compact-pending.sh
# PreCompact hook: records that a teammate session is compacting.
#
# Per hooks-ref.md, PreCompact has no decision control. This hook only writes
# session-side state so TeammateIdle can retire the teammate later if needed.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
# shellcheck source=../../../runtime/lib/session-common.sh
source "$REPO_ROOT/shared/runtime/lib/session-common.sh"
px_load_session || exit 0

INPUT=$(cat)
AGENT=$(px_normalize_agent "$(echo "$INPUT" | jq -r '.agent_type // empty' 2>/dev/null || true)")
px_is_teammate "$AGENT" || exit 0

AGENT_SHORT=$(px_short_agent "$AGENT")
TRIGGER=$(echo "$INPUT" | jq -r '.trigger // "unknown"' 2>/dev/null || echo "unknown")
PENDING_FILE=$(px_compact_pending_file "$AGENT_SHORT")
STATE_JSON=$(px_state_json "$AGENT_SHORT")

jq -n \
  --arg agent "$AGENT_SHORT" \
  --arg trigger "$TRIGGER" \
  --arg transcript_path "$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || true)" \
  --arg created_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
  --argjson state "$STATE_JSON" \
  '{
    agent: $agent,
    trigger: $trigger,
    transcript_path: $transcript_path,
    created_at: $created_at,
    state: $state
  }' > "$PENDING_FILE"

exit 0
