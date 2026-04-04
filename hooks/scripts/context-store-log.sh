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
  local logfile
  logfile=$(cs_log_file)

  # Strip project dir prefix for readability
  local short_file="${file#"${CLAUDE_PROJECT_DIR:-}"}"
  short_file="${short_file#/}"

  local ts
  ts=$(date -u +"%H:%M:%S")

  printf "%s  %-10s %-28s %-40s %s\n" "$ts" "$event" "$agent" "$short_file" "($detail)" >> "$logfile" 2>/dev/null || true
}

cs_log_file() {
  echo "${CLAUDE_PROJECT_DIR:-.}/.popcorn-xp/context-store.log"
}

cs_checkpoint_cursor_file() {
  local team_dir="${1:?}"
  echo "$team_dir/.checkpoint-cursor"
}

cs_log_line_count() {
  local logfile="${1:-$(cs_log_file)}"
  if [ -f "$logfile" ]; then
    wc -l < "$logfile" | tr -d ' '
  else
    echo 0
  fi
}

cs_edit_count_since_cursor() {
  local logfile="${1:?}" cursor_file="${2:?}"
  local cursor=0
  if [ -f "$cursor_file" ]; then
    cursor=$(cat "$cursor_file" 2>/dev/null || echo 0)
    [[ "$cursor" =~ ^[0-9]+$ ]] || cursor=0
  fi

  [ -f "$logfile" ] || {
    echo 0
    return 0
  }

  awk -v cursor="$cursor" 'NR > cursor && $2 == "EDIT" { count++ } END { print count + 0 }' "$logfile"
}
