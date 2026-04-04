#!/bin/bash
set -euo pipefail

# cleanup-context-store.sh
# PostToolUse hook on TeamDelete: removes shared context-store artifacts after
# team cleanup completes.

POPCORN_DIR="${CLAUDE_PROJECT_DIR:-.}/.popcorn-xp"
[ -d "$POPCORN_DIR" ] || exit 0

rm -f \
  "$POPCORN_DIR/context-store.json" \
  "$POPCORN_DIR/context-store.log" \
  "$POPCORN_DIR/context-store.json.lock"

exit 0
