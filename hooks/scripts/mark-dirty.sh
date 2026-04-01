#!/bin/bash
set -euo pipefail

# mark-dirty.sh
# PreToolUse hook on Edit/Write: sets a dirty flag when files are edited.
# The remind-checkpoint.sh TeammateIdle hook checks this flag and nudges
# the driver to send a checkpoint if they haven't since the last edit.
# No-op when no active popcorn-xp session.

POPCORN_DIR="${CLAUDE_PROJECT_DIR:-.}/.popcorn-xp"
[ ! -d "$POPCORN_DIR" ] && exit 0

touch "$POPCORN_DIR/.dirty"
exit 0
