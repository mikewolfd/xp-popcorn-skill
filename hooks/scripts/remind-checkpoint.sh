#!/bin/bash
set -euo pipefail

# remind-checkpoint.sh
# TeammateIdle hook: reminds driver to checkpoint after uncheckpointed edits.
# Checks for .dirty flag set by mark-dirty.sh (PreToolUse on Edit/Write).
# The flag is cleared by auto-log-messages.sh when a checkpoint is logged.
# Non-blocking — just a nudge via systemMessage.
# No-op when no active popcorn-xp session or no dirty flag.

POPCORN_DIR="${CLAUDE_PROJECT_DIR:-.}/.popcorn-xp"
[ ! -f "$POPCORN_DIR/.dirty" ] && exit 0

echo '{"systemMessage":"Popcorn XP: You edited files since your last checkpoint. Send a checkpoint to your navigator — they can only advise on what they can see. Use summary: \"checkpoint: ...\" so it gets logged automatically."}'

# Remove flag so we don't nag on every idle cycle
rm -f "$POPCORN_DIR/.dirty"

exit 0
