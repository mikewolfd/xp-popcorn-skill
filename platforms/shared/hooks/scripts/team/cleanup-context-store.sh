#!/bin/bash
set -euo pipefail

# cleanup-context-store.sh
# PostToolUse hook on TeamDelete: removes shared context-store artifacts after
# team cleanup completes.
# Subagent mode: no-op — team transport / soft-lock log is not used.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../../.." && pwd)"
# shellcheck source=../../../../shared/runtime/lib/session-common.sh
source "$REPO_ROOT/shared/runtime/lib/session-common.sh"

POPCORN_DIR="${CLAUDE_PROJECT_DIR:-.}/.popcorn-xp"
[ -d "$POPCORN_DIR" ] || exit 0

px_load_session || exit 0
px_is_subagent_mode && exit 0

rm -f \
  "$POPCORN_DIR/context-store.log"

exit 0
