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

# px_runtime_mode — "subagent" (default if .runtime-mode missing) or "team" (explicit opt-in)
px_runtime_mode() {
  local f="$TEAM_DIR/.runtime-mode" m
  [ ! -f "$f" ] && { echo "subagent"; return 0; }
  m=$(tr '[:upper:]' '[:lower:]' < "$f" | tr -d '[:space:]')
  if [ "$m" = "subagent" ]; then
    echo "subagent"
  else
    echo "team"
  fi
}

px_is_subagent_mode() {
  [ "$(px_runtime_mode)" = "subagent" ]
}

px_normalize_agent() {
  local raw="${1:-}"
  if [ -z "$raw" ] || [ "$raw" = "null" ] || [ "$raw" = "unknown" ]; then
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

px_is_nav_task() {
  local task_id="${1:-}" task_hint="${2:-}"

  if [ -n "$task_id" ] && printf '%s' "$task_id" | grep -qiE '(^|[^[:alnum:]])nav([^[:alnum:]]|$)|navigate|navigator'; then
    return 0
  fi

  if [ -n "$task_hint" ] && printf '%s' "$task_hint" | grep -qiE '(^|[^[:alnum:]])nav([^[:alnum:]]|$)|navigate|navigator'; then
    return 0
  fi

  return 1
}

px_is_teammate() {
  local normalized="${1:-}"
  [ -n "$normalized" ] && [ "$normalized" != "lead" ] && [ "$normalized" != "unknown" ]
}

px_state_file() {
  local short_agent="${1:?}"
  echo "$STATE_DIR/${short_agent}.json"
}

px_compact_pending_file() {
  local short_agent="${1:?}"
  echo "$TEAM_DIR/.compact-pending-${short_agent}.json"
}

px_compact_stop_file() {
  local short_agent="${1:?}"
  echo "$TEAM_DIR/.compact-stop-${short_agent}.json"
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
  jq --arg updated_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" ${args[@]+"${args[@]}"} "$jq_filter | .updated_at = \$updated_at" "$file" > "$tmp" && mv "$tmp" "$file"
}

px_has_write_set() {
  local short_agent="${1:?}"
  [ "$(px_state_json "$short_agent" | jq -r '(.write_set // []) | length' 2>/dev/null || echo 0)" -gt 0 ]
}

# px_unresolved_advice ADVICE_PATH [TYPE...]
# For each TYPE (default: OBJECTION SMELL STEER FYI), prints "TYPE N" for each
# type with N > 0 unresolved items.  "Unresolved" means an "--- open" entry
# exists whose ID has no matching "--- OUTCOME" resolution line.
# Output is one line per type that has unresolved items; prints nothing when all clear.
px_unresolved_advice() {
  local advice_path="${1:?}"
  shift
  local types
  if [ $# -gt 0 ]; then
    types=("$@")
  else
    types=(OBJECTION SMELL STEER FYI)
  fi
  [ -f "$advice_path" ] || return 0
  local TYPE open_ids count id
  for TYPE in "${types[@]}"; do
    open_ids=$(grep -oE "### $TYPE ([^ ]+) — open" "$advice_path" | sed "s/### $TYPE \([^ ]*\) — open/\1/" || true)
    count=0
    for id in $open_ids; do
      if ! grep -iqE "^### $id — (FIXED|REJECTED|INCORPORATED|NOTED)" "$advice_path"; then
        count=$((count + 1))
      fi
    done
    if [ "$count" -gt 0 ]; then echo "$TYPE $count"; fi
  done
  return 0
}

# px_advice_status_rows ADVICE_PATH
# Emits TSV rows describing the effective latest status for each advice item:
#   TYPE<TAB>ID<TAB>STATUS<TAB>AUTHOR<TAB>DETAIL
# STATUS is one of OPEN, FIXED, REJECTED, INCORPORATED, NOTED.
# DETAIL comes from the original open entry description.
px_advice_status_rows() {
  local advice_path="${1:?}"
  [ -f "$advice_path" ] || return 0

  python3 - "$advice_path" <<'PY'
import re
import sys

path = sys.argv[1]
open_re = re.compile(r"^### (OBJECTION|SMELL|STEER|FYI) ([^ ]+) — open(?: \(by ([^)]+)\))?$")
resolve_re = re.compile(r"^### ([^ ]+) — (FIXED|REJECTED|INCORPORATED|NOTED)$")

rows = []
current = None

with open(path, "r", encoding="utf-8") as handle:
    for raw_line in handle:
        line = raw_line.rstrip("\n")
        match = open_re.match(line)
        if match:
            current = {
                "type": match.group(1),
                "id": match.group(2),
                "author": match.group(3) or "",
                "status": "OPEN",
                "detail_lines": [],
            }
            rows.append(current)
            continue

        match = resolve_re.match(line)
        if match:
            target_id = match.group(1)
            outcome = match.group(2)
            for row in rows:
                if row["id"] == target_id:
                    row["status"] = outcome
            current = None
            continue

        if current is not None and not line.startswith("### "):
            if line.strip():
                current["detail_lines"].append(line.strip())

for row in rows:
    detail = " ".join(row["detail_lines"]).strip()
    print("\t".join([row["type"], row["id"], row["status"], row["author"], detail]))
PY
}

# px_effective_open_advice_counts ADVICE_PATH [TYPE...]
# Prints "TYPE N" rows using the effective latest status from px_advice_status_rows.
px_effective_open_advice_counts() {
  local advice_path="${1:?}"
  shift
  local types
  if [ $# -gt 0 ]; then
    types=("$@")
  else
    types=(OBJECTION SMELL STEER FYI)
  fi

  [ -f "$advice_path" ] || return 0

  local rows type count
  rows="$(px_advice_status_rows "$advice_path")"
  [ -z "$rows" ] && return 0

  for type in "${types[@]}"; do
    count=$(printf '%s\n' "$rows" | awk -F '\t' -v type="$type" '$1 == type && $3 == "OPEN" { count++ } END { print count + 0 }')
    if [ "${count:-0}" -gt 0 ]; then
      echo "$type $count"
    fi
  done
  return 0
}

px_normalize_path() {
  local p="${1:?}"
  # Strip leading ./ so "./foo" and "foo" both normalize the same way
  p="${p#./}"
  if [[ "$p" == /* ]]; then
    echo "$p"
  else
    echo "${CLAUDE_PROJECT_DIR:-.}/$p"
  fi
}

px_path_in_write_set() {
  local short_agent="${1:?}" file_path="${2:?}"
  local abs_file proj
  abs_file=$(px_normalize_path "$file_path")
  proj="${CLAUDE_PROJECT_DIR:-.}"
  px_state_json "$short_agent" | jq -e --arg path "$abs_file" --arg proj "$proj" '
    (.write_set // []) | map(
      # Strip leading ./ then prepend proj if not absolute
      ltrimstr("./") | if startswith("/") then . else $proj + "/" + . end
    ) | index($path) != null
  ' >/dev/null 2>&1
}

# Last driver slug from LOG.md: walk ## Task lines bottom-up; first Driver @name
# wins. Placeholder lines use "Driver (pending claim)" (no @) and do not match.
px_last_task_log_driver() {
  local logf="${1:?}"
  local line cand
  [ -f "$logf" ] || return 0
  # Bash 3.2–compatible (no mapfile): newest ## Task lines first.
  while IFS= read -r line; do
    if [[ "$line" =~ Driver[[:space:]]+@([^,]+) ]]; then
      cand="${BASH_REMATCH[1]// /}"
      if [[ -n "$cand" ]]; then
        echo "$cand"
        return 0
      fi
    fi
  done < <(awk '/^## Task/ { a[++c] = $0 } END { for (i = c; i >= 1; i--) print a[i] }' "$logf" 2>/dev/null)
  echo ""
}
