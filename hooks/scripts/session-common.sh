#!/bin/bash

# Shared helpers for popcorn-xp hook scripts.

px_load_session() {
  POPCORN_DIR="${CLAUDE_PROJECT_DIR:-.}/.popcorn-xp"
  TEAM=$(cat "$POPCORN_DIR/.active-team" 2>/dev/null || true)
  [ -z "$TEAM" ] && return 1

  TEAM_DIR="$POPCORN_DIR/$TEAM"
  [ ! -d "$TEAM_DIR" ] && return 1

  STATE_DIR="$TEAM_DIR/agent-state"
  return 0
}

px_normalize_agent() {
  local raw="${1:-}"
  if [ -z "$raw" ] || [ "$raw" = "null" ]; then
    if [ -n "${CLAUDE_CODE_COORDINATOR_MODE:-}" ]; then
      echo "lead"
    else
      echo "unknown"
    fi
    return 0
  fi

  if [ "$raw" = "unknown" ]; then
    if [ -n "${CLAUDE_CODE_COORDINATOR_MODE:-}" ]; then
      echo "lead"
    else
      echo "unknown"
    fi
    return 0
  fi

  if [[ "$raw" == popcorn-xp:* ]] || [ "$raw" = "lead" ]; then
    echo "$raw"
  else
    echo "popcorn-xp:$raw"
  fi
}

px_short_agent() {
  local normalized="${1:-}"
  echo "${normalized#popcorn-xp:}"
}

px_is_teammate() {
  local normalized="${1:-}"
  [ -n "$normalized" ] && [ "$normalized" != "lead" ] && [ "$normalized" != "unknown" ]
}

px_state_file() {
  local short_agent="${1:?}"
  echo "$STATE_DIR/${short_agent}.json"
}

px_state_json() {
  local short_agent="${1:?}"
  local file
  file=$(px_state_file "$short_agent")
  if [ -f "$file" ]; then
    cat "$file"
  else
    echo '{}'
  fi
}

px_state_field() {
  local short_agent="${1:?}" field="${2:?}"
  px_state_json "$short_agent" | jq -r --arg field "$field" '.[$field] // empty' 2>/dev/null || true
}

px_init_state() {
  local short_agent="${1:?}" task_id="${2:-}"
  mkdir -p "$STATE_DIR"
  jq -n \
    --arg agent "$short_agent" \
    --arg task_id "$task_id" \
    --arg updated_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    '{
      agent: $agent,
      role: "",
      phase: "",
      task_id: $task_id,
      blocked_on: "",
      next_action: "",
      navigator_ready: false,
      navigator_artifact_kind: "",
      navigator_artifact_status: "",
      write_set: [],
      updated_at: $updated_at
    }'
}

px_ensure_state_file() {
  local short_agent="${1:?}" task_id="${2:-}"
  local file
  file=$(px_state_file "$short_agent")
  mkdir -p "$STATE_DIR"
  [ -f "$file" ] || px_init_state "$short_agent" "$task_id" > "$file"
  echo "$file"
}

px_update_state() {
  local short_agent="${1:?}" task_id="${2:-}"
  local file tmp jq_filter last_index
  local -a args
  shift 2
  args=("$@")
  last_index=$((${#args[@]} - 1))
  jq_filter="${args[$last_index]}"
  unset "args[$last_index]"
  file=$(px_ensure_state_file "$short_agent" "$task_id")
  tmp=$(mktemp)
  jq "${args[@]}" "$jq_filter" "$file" > "$tmp" && mv "$tmp" "$file"
}

px_has_write_set() {
  local short_agent="${1:?}"
  [ "$(px_state_json "$short_agent" | jq -r '(.write_set // []) | length' 2>/dev/null || echo 0)" -gt 0 ]
}

px_path_in_write_set() {
  local short_agent="${1:?}" file_path="${2:?}"
  px_state_json "$short_agent" | jq -e --arg path "$file_path" '
    (.write_set // []) | index($path) != null
  ' >/dev/null 2>&1
}
