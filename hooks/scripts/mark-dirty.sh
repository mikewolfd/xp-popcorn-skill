#!/bin/bash
set -euo pipefail

# mark-dirty.sh
# PreToolUse hook on Edit/Write: sets a dirty flag when files are edited.
# The remind-checkpoint.sh TeammateIdle hook checks this flag and nudges
# the driver to send a checkpoint if they haven't since the last edit.
# No-op when no active popcorn-xp session.

POPCORN_DIR="${CLAUDE_PROJECT_DIR:-.}/.popcorn-xp"
TEAM=$(cat "$POPCORN_DIR/.active-team" 2>/dev/null || true)
[ -z "$TEAM" ] && exit 0
[ ! -d "$POPCORN_DIR/$TEAM" ] && exit 0

touch "$POPCORN_DIR/$TEAM/.dirty"
exit 0
