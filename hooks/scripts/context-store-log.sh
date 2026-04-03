#!/bin/bash
# context-store-log.sh
# Sourced by context-store hooks to append events to context-store.log.
# Not a standalone hook — provides the cs_log function.
#
# Usage (from another hook script):
#   source "${CLAUDE_PLUGIN_ROOT:-$(dirname "$0")/..}/hooks/scripts/context-store-log.sh"
#   cs_log "READ" "$AGENT" "$FILE_PATH" "new entry"

cs_log() {
  local event="$1" agent="$2" file="$3" detail="$4"
  local popcorn_dir="${CLAUDE_PROJECT_DIR:-.}/.popcorn-xp"
  local logfile="$popcorn_dir/context-store.log"

  # Strip project dir prefix for readability
  local short_file="${file#"${CLAUDE_PROJECT_DIR:-}"}"
  short_file="${short_file#/}"

  local ts
  ts=$(date -u +"%H:%M:%S")

  printf "%s  %-10s %-28s %-40s %s\n" "$ts" "$event" "$agent" "$short_file" "($detail)" >> "$logfile" 2>/dev/null || true
}
