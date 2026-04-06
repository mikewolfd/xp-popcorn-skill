#!/bin/bash
# context-store-log.sh
# Sourced by context-store hooks to append events to context-store.log.
# Not a standalone hook — provides the cs_log function.
#
# Usage (from another hook script):
#   source ".../hooks/scripts/team/context-store-log.sh" (path via ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/team/context-store-log.sh)
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

cs_review_cursor_file() {
  local team_dir="${1:?}" agent="${2:?}"
  echo "$team_dir/.review-cursor-${agent}"
}

cs_edit_count_since_review_cursor() {
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

# cs_file_state FILE_PATH
# Returns the last EDIT event for FILE_PATH from context-store.log.
# Outputs "AGENT TIMESTAMP" (space-separated) if an EDIT was found, nothing if not.
# FILE_PATH may be absolute; normalized the same way cs_log() does.
cs_file_state() {
  local file_path="${1:?}"
  local logfile
  logfile=$(cs_log_file)
  [ -f "$logfile" ] || return 0

  local short_file="${file_path#"${CLAUDE_PROJECT_DIR:-}"}"
  short_file="${short_file#/}"

  # Log format: TIME  EDIT  AGENT  SHORT_FILE  (detail)
  # Single awk pass: find last EDIT line for this exact file path
  local result
  result=$(awk -v file="$short_file" '$2 == "EDIT" && $4 == file { a=$3; t=$1 } END { if(a) print a,t }' "$logfile")
  [ -n "$result" ] && echo "$result"
  return 0
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
