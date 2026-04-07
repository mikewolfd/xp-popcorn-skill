#!/bin/bash
set -euo pipefail

# Codex Stop hook: OBJECTION gate using the same script as Claude TaskCompleted.
# Maps exit 2 + stderr to JSON {decision, reason} per research/official/codex/hooks.md.
# No active session → exit 0, JSON {continue:true}. Warnings-only stdout from advice script → allow stop.

_HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
_REPO_ROOT="$(cd "$_HOOK_DIR/../../../.." && pwd)"
# shellcheck source=../../../../shared/runtime/lib/resolve-project-dir.sh
source "$_REPO_ROOT/shared/runtime/lib/resolve-project-dir.sh"

INPUT=$(cat || true)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
[ -z "$CWD" ] && CWD="$(pwd 2>/dev/null || echo .)"
if [ -z "${CLAUDE_PROJECT_DIR:-}" ]; then
  CLAUDE_PROJECT_DIR="$(px_resolve_project_dir_from "$CWD")"
fi
export CLAUDE_PROJECT_DIR

# Resolve check-advice script from this hook's checkout (platforms/codex/subagent/hooks/ → repo root), not from cwd/git,
# so Codex sessions whose cwd is a temp or subfolder still find the vendored plugin scripts.
ADVICE_SCRIPT="$_REPO_ROOT/platforms/shared/hooks/scripts/advice/check-advice-on-complete.sh"

POPCORN="${CLAUDE_PROJECT_DIR}/.popcorn-xp"
TEAM=$(cat "$POPCORN/.active-team" 2>/dev/null || true)
if [ -z "$TEAM" ] || [ ! -f "$ADVICE_SCRIPT" ]; then
  jq -n '{continue:true}'
  exit 0
fi
[ ! -d "$POPCORN/$TEAM" ] && { jq -n '{continue:true}'; exit 0; }

tmp_out=$(mktemp)
tmp_err=$(mktemp)
set +e
bash "$ADVICE_SCRIPT" < /dev/null >"$tmp_out" 2>"$tmp_err"
rc=$?
set -e

if [ "$rc" -eq 2 ]; then
  reason=$(cat "$tmp_err" || true)
  rm -f "$tmp_out" "$tmp_err"
  jq -nc --arg r "$reason" '{decision:"block",reason:$r}'
  exit 0
fi

rm -f "$tmp_out" "$tmp_err"
# Non-blocking advice warnings: do not force continuation loops on every Stop
jq -n '{continue:true}'
exit 0
