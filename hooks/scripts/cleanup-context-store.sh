#!/bin/bash
set -euo pipefail

# cleanup-context-store.sh
# PostToolUse hook on TeamDelete: removes shared context-store artifacts after
# team cleanup completes.
# Subagent mode: no-op — team transport / soft-lock log is not used.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=session-common.sh
source "$SCRIPT_DIR/session-common.sh"

POPCORN_DIR="${CLAUDE_PROJECT_DIR:-.}/.popcorn-xp"
[ -d "$POPCORN_DIR" ] || exit 0

px_load_session || exit 0
px_is_subagent_mode && exit 0

rm -f \
  "$POPCORN_DIR/context-store.log"

exit 0
