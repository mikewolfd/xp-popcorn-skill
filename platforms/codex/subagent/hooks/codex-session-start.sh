#!/bin/bash
set -euo pipefail

# Codex SessionStart hook: remind agents when a Popcorn XP session is active.
# Input: JSON on stdin (see research/official/codex/hooks.md). Output: optional JSON
# with hookSpecificOutput.additionalContext, or exit 0 with no stdout.
#
# Codex may set cwd to a subdirectory; .popcorn-xp lives at the git root (or cwd
# when not in a repo). See shared/runtime/lib/resolve-project-dir.sh.

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
POPCORN="${CLAUDE_PROJECT_DIR}/.popcorn-xp"
TEAM=$(cat "$POPCORN/.active-team" 2>/dev/null || true)
[ -z "$TEAM" ] && exit 0
[ ! -d "$POPCORN/$TEAM" ] && exit 0

SESSION_BIN="${CLAUDE_PROJECT_DIR}/shared/runtime/bin/session"
CTX="Popcorn XP: active team \"${TEAM}\" — session root ${CLAUDE_PROJECT_DIR}/.popcorn-xp/${TEAM}. Use \"${SESSION_BIN}\" (or .popcorn-xp/${TEAM}/session) for LOG, ADVICE, state, and task bus. Subagent: set .runtime-mode to subagent. Lead playbook: popcorn-xp skill (platforms/codex/subagent/skills/popcorn-xp/SKILL.md)."

jq -nc \
  --arg ctx "$CTX" \
  '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$ctx}}'
