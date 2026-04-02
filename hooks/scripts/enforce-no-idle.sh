#!/bin/bash
set -euo pipefail

# enforce-no-idle.sh
# TeammateIdle hook: enforces the no-idle rule — agents must always be active.
# Always exits 2 to inject a reminder of productive alternatives.
# No-op when no active popcorn-xp session.

POPCORN_DIR="${CLAUDE_PROJECT_DIR:-.}/.popcorn-xp"
TEAM=$(cat "$POPCORN_DIR/.active-team" 2>/dev/null || true)
[ -z "$TEAM" ] && exit 0

echo "Popcorn XP: Agents must never idle. If you're waiting, pick something productive: review the task description, read ahead in relevant files, check ADVICE.md for unresolved items, or investigate the next problem. Idle time is wasted pairing time." >&2

exit 2
