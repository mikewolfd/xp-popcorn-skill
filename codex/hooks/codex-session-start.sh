#!/bin/bash
set -euo pipefail

# Codex SessionStart hook: remind agents when a Popcorn XP session is active.
# Input: JSON on stdin (see research/official/codex/hooks.md). Output: optional JSON
# with hookSpecificOutput.additionalContext, or exit 0 with no stdout.

INPUT=$(cat || true)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
export CLAUDE_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$CWD}"
POPCORN="${CLAUDE_PROJECT_DIR:-.}/.popcorn-xp"
TEAM=$(cat "$POPCORN/.active-team" 2>/dev/null || true)
[ -z "$TEAM" ] && exit 0
[ ! -d "$POPCORN/$TEAM" ] && exit 0

CTX="Popcorn XP: active team \"${TEAM}\" — session root .popcorn-xp/${TEAM}. Use ./bin/session (or .popcorn-xp/${TEAM}/session) for LOG, ADVICE, state, and task bus. Subagent mode: set .runtime-mode to subagent; see docs/dual-mode-codex-companion.md."

jq -nc \
  --arg ctx "$CTX" \
  '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$ctx}}'
