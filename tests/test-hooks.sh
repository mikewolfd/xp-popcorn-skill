#!/bin/bash
set -euo pipefail

# test-hooks.sh — Validates popcorn-xp hook scripts against canonical behavior.
#
# Canonical exit code semantics (hooks-ref.md):
#   exit 0 = allow action, parse stdout JSON for additionalContext
#   exit 2 = block action, feed stderr text to Claude as feedback
#   other  = non-blocking error, stderr logged but not shown
#
# Run: ./tests/test-hooks.sh
# Requires: bash 4+, no other dependencies

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOKS_DIR="$SCRIPT_DIR/hooks/scripts"
FIXTURES_DIR="$SCRIPT_DIR/tests/fixtures"

# --- Test harness ---

PASS=0
FAIL=0
ERRORS=""

assert_exit() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" -eq "$actual" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: ${label} — expected exit ${expected}, got ${actual}"
  fi
}

assert_stdout_contains() {
  local label="$1" needle="$2" stdout="$3"
  if echo "$stdout" | grep -q "$needle"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: ${label} — stdout missing '${needle}'"
  fi
}

assert_stdout_empty() {
  local label="$1" stdout="$2"
  if [ -z "$stdout" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: ${label} — expected empty stdout, got '${stdout}'"
  fi
}

assert_stderr_contains() {
  local label="$1" needle="$2" stderr="$3"
  if echo "$stderr" | grep -q "$needle"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: ${label} — stderr missing '${needle}'"
  fi
}

assert_stderr_not_contains() {
  local label="$1" needle="$2" stderr="$3"
  if echo "$stderr" | grep -q "$needle"; then
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: ${label} — stderr should not contain '${needle}'"
  else
    PASS=$((PASS + 1))
  fi
}

assert_stdout_not_contains() {
  local label="$1" needle="$2" stdout="$3"
  if echo "$stdout" | grep -q "$needle"; then
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: ${label} — stdout should not contain '${needle}'"
  else
    PASS=$((PASS + 1))
  fi
}

# Run a hook script, capture stdout, stderr, and exit code separately
run_hook() {
  local script="$1"
  shift
  local stdout_file stderr_file
  stdout_file=$(mktemp)
  stderr_file=$(mktemp)
  local rc=0
  env CLAUDE_PROJECT_DIR="$TMPDIR_ROOT" bash "$HOOKS_DIR/$script" "$@" \
    >"$stdout_file" 2>"$stderr_file" || rc=$?
  LAST_STDOUT=$(cat "$stdout_file")
  LAST_STDERR=$(cat "$stderr_file")
  LAST_RC=$rc
  rm -f "$stdout_file" "$stderr_file"
}

# Run a hook script with stdin input
run_hook_stdin() {
  local script="$1" stdin_data="$2"
  shift 2
  local stdout_file stderr_file
  stdout_file=$(mktemp)
  stderr_file=$(mktemp)
  local rc=0
  echo "$stdin_data" | env CLAUDE_PROJECT_DIR="$TMPDIR_ROOT" bash "$HOOKS_DIR/$script" "$@" \
    >"$stdout_file" 2>"$stderr_file" || rc=$?
  LAST_STDOUT=$(cat "$stdout_file")
  LAST_STDERR=$(cat "$stderr_file")
  LAST_RC=$rc
  rm -f "$stdout_file" "$stderr_file"
}

run_hook_stdin_file() {
  local script="$1" fixture="$2"
  shift 2
  local stdout_file stderr_file
  stdout_file=$(mktemp)
  stderr_file=$(mktemp)
  local rc=0
  cat "$fixture" | env CLAUDE_PROJECT_DIR="$TMPDIR_ROOT" bash "$HOOKS_DIR/$script" "$@" \
    >"$stdout_file" 2>"$stderr_file" || rc=$?
  LAST_STDOUT=$(cat "$stdout_file")
  LAST_STDERR=$(cat "$stderr_file")
  LAST_RC=$rc
  rm -f "$stdout_file" "$stderr_file"
}

# --- Fixture setup ---

TMPDIR_ROOT=$(mktemp -d)
TEAM="test-team"
POPCORN="$TMPDIR_ROOT/.popcorn-xp"

setup_session() {
  rm -rf "$POPCORN"
  mkdir -p "$POPCORN/$TEAM" "$POPCORN/$TEAM/agent-state"
  echo "$TEAM" > "$POPCORN/.active-team"
  printf "# Advice\n" > "$POPCORN/$TEAM/ADVICE.md"
}

checkpoint_now() {
  local logfile="$POPCORN/context-store.log"
  if [ -f "$logfile" ]; then
    wc -l < "$logfile" | tr -d ' ' > "$POPCORN/$TEAM/.checkpoint-cursor"
  else
    echo 0 > "$POPCORN/$TEAM/.checkpoint-cursor"
  fi
}

write_state() {
  local agent="$1" role="$2" phase="$3" task_id="$4" blocked_on="$5" next_action="$6"
  local nav_ready="${7:-false}" nav_kind="${8:-}" nav_status="${9:-}" writes="${10:-[]}"
  jq -n \
    --arg agent "$agent" \
    --arg role "$role" \
    --arg phase "$phase" \
    --arg task_id "$task_id" \
    --arg blocked_on "$blocked_on" \
    --arg next_action "$next_action" \
    --argjson navigator_ready "$nav_ready" \
    --arg nav_kind "$nav_kind" \
    --arg nav_status "$nav_status" \
    --argjson write_set "$writes" \
    '{
      agent: $agent,
      role: $role,
      phase: $phase,
      task_id: $task_id,
      blocked_on: $blocked_on,
      next_action: $next_action,
      navigator_ready: $navigator_ready,
      navigator_artifact_kind: $nav_kind,
      navigator_artifact_status: $nav_status,
      write_set: $write_set
    }' > "$POPCORN/$TEAM/agent-state/$agent.json"
}

teardown() {
  rm -rf "$TMPDIR_ROOT"
}
trap teardown EXIT

# ============================================================
# 1. No-op tests: every script exits 0 when no active session
# ============================================================

echo "--- No-op tests (no active session) ---"

rm -rf "$POPCORN"  # ensure no session

for script in check-advice-on-complete.sh remind-unread-advice.sh remind-checkpoint.sh \
              enforce-no-idle.sh check-objections.sh check-rotation.sh check-retro-before-delete.sh \
              context-store-check.sh context-store-mark-dirty.sh cleanup-context-store.sh; do
  if [ "$script" = "check-rotation.sh" ]; then
    run_hook_stdin "$script" '{}'
  elif [ "$script" = "context-store-check.sh" ] || [ "$script" = "context-store-mark-dirty.sh" ]; then
    run_hook_stdin "$script" '{"tool_input":{"file_path":"/tmp/test.txt"},"agent_type":"popcorn-xp:scout"}'
  else
    run_hook "$script"
  fi
  assert_exit "no-op: $script" 0 "$LAST_RC"
  assert_stdout_empty "no-op stdout: $script" "$LAST_STDOUT"
done

# context-store-update-read also no-op without session
run_hook_stdin "context-store-update-read.sh" \
  '{"tool_input":{"file_path":"/tmp/test.txt"},"tool_response":"content","agent_type":"popcorn-xp:scout"}'
assert_exit "no-op: context-store-update-read.sh" 0 "$LAST_RC"
assert_stdout_empty "no-op stdout: context-store-update-read.sh" "$LAST_STDOUT"

run_hook_stdin "mark-compact-pending.sh" '{"hook_event_name":"PreCompact","trigger":"auto","agent_type":"popcorn-xp:craftsman"}'
assert_exit "no-op: mark-compact-pending.sh" 0 "$LAST_RC"
assert_stdout_empty "no-op stdout: mark-compact-pending.sh" "$LAST_STDOUT"

run_hook_stdin "record-compact-summary.sh" '{"hook_event_name":"PostCompact","trigger":"auto","compact_summary":"summary","agent_type":"popcorn-xp:craftsman"}'
assert_exit "no-op: record-compact-summary.sh" 0 "$LAST_RC"
assert_stdout_empty "no-op stdout: record-compact-summary.sh" "$LAST_STDOUT"

# ============================================================
# 2. H6: Non-blocking output uses additionalContext, not systemMessage
# ============================================================

echo "--- H6: additionalContext field name ---"

# check-advice-on-complete.sh warning path (open SMELLs, no OBJECTIONs)
setup_session
cat >> "$POPCORN/$TEAM/ADVICE.md" <<'EOF'

### SMELL SML-1-01 — open
Test smell
EOF

run_hook "check-advice-on-complete.sh"
assert_exit "H6 warning path exit" 0 "$LAST_RC"
assert_stdout_contains "H6 additionalContext" "additionalContext" "$LAST_STDOUT"
assert_stdout_not_contains "H6 no systemMessage" "systemMessage" "$LAST_STDOUT"

# check-rotation.sh (simulate single driver, remaining tasks)
# This needs task files — skip for now, tested structurally via grep below

# ============================================================
# 3. H5: Blocking output is plain text stderr, not JSON
# ============================================================

echo "--- H5: Plain text stderr on exit 2 ---"

# check-advice-on-complete.sh with open OBJECTION
setup_session
cat >> "$POPCORN/$TEAM/ADVICE.md" <<'EOF'

### OBJECTION OBJ-1-01 — open
Test objection
EOF

run_hook "check-advice-on-complete.sh"
assert_exit "H5 OBJECTION blocks" 2 "$LAST_RC"
assert_stderr_contains "H5 has message" "unresolved OBJECTION" "$LAST_STDERR"
assert_stderr_not_contains "H5 no JSON in stderr" '{"decision"' "$LAST_STDERR"
assert_stderr_not_contains "H5 no JSON braces" '{"' "$LAST_STDERR"

# check-objections.sh with open OBJECTION
run_hook "check-objections.sh"
assert_exit "H5 check-objections blocks" 2 "$LAST_RC"
assert_stderr_not_contains "H5 check-objections no JSON" '{"' "$LAST_STDERR"

# check-retro-before-delete.sh without RETRO.md
setup_session
run_hook "check-retro-before-delete.sh"
assert_exit "H5 retro blocks" 2 "$LAST_RC"
assert_stderr_contains "H5 retro message" "RETRO.md" "$LAST_STDERR"
assert_stderr_not_contains "H5 retro no JSON" '{"' "$LAST_STDERR"

# check-retro-before-delete.sh with stub RETRO.md (< 5 lines)
printf "# Retro\nstub\n" > "$POPCORN/$TEAM/RETRO.md"
run_hook "check-retro-before-delete.sh"
assert_exit "H5 retro stub blocks" 2 "$LAST_RC"
assert_stderr_not_contains "H5 retro stub no JSON" '{"' "$LAST_STDERR"

# check-retro-before-delete.sh with real RETRO.md (>= 5 lines)
printf "# Retro\nline1\nline2\nline3\nline4\nline5\n" > "$POPCORN/$TEAM/RETRO.md"
run_hook "check-retro-before-delete.sh"
assert_exit "H5 retro real allows" 0 "$LAST_RC"

# cleanup-context-store.sh removes store artifacts after team delete
echo '{}' > "$POPCORN/context-store.json"
echo '12:00:00 READ popcorn-xp:scout file.txt new entry' > "$POPCORN/context-store.log"
touch "$POPCORN/context-store.json.lock"
run_hook "cleanup-context-store.sh"
assert_exit "H5 cleanup context store exits 0" 0 "$LAST_RC"
if [ ! -f "$POPCORN/context-store.json" ] && [ ! -f "$POPCORN/context-store.log" ] && [ ! -f "$POPCORN/context-store.json.lock" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: H5 cleanup-context-store should remove context store artifacts"
fi

# ============================================================
# 4. H1: TeammateIdle hooks exit 2 when they have content
# ============================================================

echo "--- H1: TeammateIdle exit codes ---"

# remind-unread-advice.sh exits 2 when open advice exists
setup_session
cat >> "$POPCORN/$TEAM/ADVICE.md" <<'EOF'

### SMELL SML-2-01 — open
Something smells
EOF

run_hook "remind-unread-advice.sh"
assert_exit "H1 remind-advice blocks" 2 "$LAST_RC"

# remind-unread-advice.sh exits 0 when no open advice
setup_session
run_hook "remind-unread-advice.sh"
assert_exit "H1 remind-advice no-op" 0 "$LAST_RC"

# remind-checkpoint.sh exits 2 when edit events exist since last checkpoint
setup_session
write_state "craftsman" "driver" "driving" "2" "" "checkpoint current progress"
run_hook_stdin "context-store-mark-dirty.sh" \
  '{"tool_input":{"file_path":"'"$TMPDIR_ROOT/h1-edit.ts"'"},"agent_type":"popcorn-xp:craftsman"}'
run_hook_stdin "remind-checkpoint.sh" '{"teammate_name":"craftsman"}'
assert_exit "H1 remind-checkpoint blocks" 2 "$LAST_RC"
assert_stderr_contains "H1 remind-checkpoint mentions edit count" "1 file edit" "$LAST_STDERR"

# remind-checkpoint.sh exits 0 when no edits exist since cursor
setup_session
write_state "craftsman" "driver" "driving" "2" "" "checkpoint current progress"
echo 0 > "$POPCORN/$TEAM/.checkpoint-cursor"
run_hook_stdin "remind-checkpoint.sh" '{"teammate_name":"craftsman"}'
assert_exit "H1 remind-checkpoint no-op" 0 "$LAST_RC"

# enforce-no-idle.sh blocks untracked working state
setup_session
run_hook_stdin "enforce-no-idle.sh" '{"teammate_name":"craftsman"}'
assert_exit "H1 enforce-no-idle blocks" 2 "$LAST_RC"

# ============================================================
# 5. H3: Flexible ID patterns — non-standard IDs detected
# ============================================================

echo "--- H3: Flexible ID patterns ---"

# check-advice-on-complete.sh detects non-standard OBJECTION ID
setup_session
cat >> "$POPCORN/$TEAM/ADVICE.md" <<'EOF'

### OBJECTION REV2-B1 — open
Non-standard ID objection
EOF

run_hook "check-advice-on-complete.sh"
assert_exit "H3 non-standard OBJECTION blocks" 2 "$LAST_RC"

# check-objections.sh detects non-standard OBJECTION ID
run_hook "check-objections.sh"
assert_exit "H3 check-objections non-standard blocks" 2 "$LAST_RC"

# remind-unread-advice.sh detects non-standard SMELL ID
setup_session
cat >> "$POPCORN/$TEAM/ADVICE.md" <<'EOF'

### SMELL custom-smell-id — open
Non-standard SMELL
EOF

run_hook "remind-unread-advice.sh"
assert_exit "H3 non-standard SMELL detected" 2 "$LAST_RC"
assert_stderr_contains "H3 SMELL in message" "SMELL" "$LAST_STDERR"

# Standard IDs still work
setup_session
cat >> "$POPCORN/$TEAM/ADVICE.md" <<'EOF'

### OBJECTION OBJ-3-01 — open
Standard ID
EOF

run_hook "check-advice-on-complete.sh"
assert_exit "H3 standard ID still works" 2 "$LAST_RC"

# ============================================================
# 6. H4: Case-insensitive resolution matching
# ============================================================

echo "--- H4: Case-insensitive resolution ---"

# Lowercase "fixed" resolves an OBJECTION
setup_session
cat >> "$POPCORN/$TEAM/ADVICE.md" <<'EOF'

### OBJECTION OBJ-4-01 — open
Test objection

### OBJ-4-01 — fixed
resolved in lowercase
EOF

run_hook "check-advice-on-complete.sh"
assert_exit "H4 lowercase fixed resolves" 0 "$LAST_RC"

# Mixed case "Fixed" resolves
setup_session
cat >> "$POPCORN/$TEAM/ADVICE.md" <<'EOF'

### OBJECTION OBJ-4-02 — open
Test objection

### OBJ-4-02 — Fixed
resolved in mixed case
EOF

run_hook "check-advice-on-complete.sh"
assert_exit "H4 mixed case resolves" 0 "$LAST_RC"

# Uppercase still works
setup_session
cat >> "$POPCORN/$TEAM/ADVICE.md" <<'EOF'

### OBJECTION OBJ-4-03 — open
Test objection

### OBJ-4-03 — REJECTED
rejected properly
EOF

run_hook "check-advice-on-complete.sh"
assert_exit "H4 uppercase REJECTED resolves" 0 "$LAST_RC"

# NOTED and INCORPORATED also resolve
setup_session
cat >> "$POPCORN/$TEAM/ADVICE.md" <<'EOF'

### OBJECTION OBJ-4-04 — open
Test objection

### OBJ-4-04 — noted
lowercase noted
EOF

run_hook "check-advice-on-complete.sh"
assert_exit "H4 lowercase noted resolves" 0 "$LAST_RC"

# Unresolved still blocks
setup_session
cat >> "$POPCORN/$TEAM/ADVICE.md" <<'EOF'

### OBJECTION OBJ-4-05 — open
No resolution here
EOF

run_hook "check-advice-on-complete.sh"
assert_exit "H4 unresolved still blocks" 2 "$LAST_RC"

# ============================================================
# 7. H2: enforce-no-idle.sh phase behavior
# ============================================================

echo "--- H2: enforce-no-idle phases ---"

# Phase 4 (working): no signal files — blocks with guidance
setup_session
run_hook_stdin "enforce-no-idle.sh" '{"teammate_name":"craftsman"}'
assert_exit "H2 working phase blocks" 2 "$LAST_RC"
assert_stderr_contains "H2 working phase guidance" "declared state" "$LAST_STDERR"

# No-op when no session
rm -rf "$POPCORN"
run_hook_stdin "enforce-no-idle.sh" '{"teammate_name":"craftsman"}'
assert_exit "H2 no-op without session" 0 "$LAST_RC"

# Phase 2 (retro pending): .retro-requested exists, no retro file — nudges
setup_session
touch "$POPCORN/$TEAM/.retro-requested"
run_hook_stdin "enforce-no-idle.sh" '{"teammate_name":"craftsman"}'
assert_exit "H2 retro pending blocks" 2 "$LAST_RC"
assert_stderr_contains "H2 retro pending mentions retro" "retro" "$LAST_STDERR"
assert_stderr_contains "H2 retro pending mentions agent" "craftsman" "$LAST_STDERR"

# Phase 3 (retro submitted): .retro-requested + .retro-{agent}.md exist — allows idle
setup_session
touch "$POPCORN/$TEAM/.retro-requested"
printf 'It went well\n' > "$POPCORN/$TEAM/.retro-craftsman.md"
run_hook_stdin "enforce-no-idle.sh" '{"teammate_name":"craftsman"}'
assert_exit "H2 retro done allows idle" 0 "$LAST_RC"

# Explicit waiting state allows idle once READY is published
setup_session
write_state "craftsman" "navigator" "waiting_on_driver" "3" "expert" "Wait for next checkpoint" true "risk_check" "published"
run_hook_stdin "enforce-no-idle.sh" '{"teammate_name":"craftsman"}'
assert_exit "H2 waiting_on_driver allows idle" 0 "$LAST_RC"

# Replay fixture for TeammateIdle behaves the same
run_hook_stdin_file "enforce-no-idle.sh" "$FIXTURES_DIR/teammateidle-craftsman.json"
assert_exit "H2 waiting_on_driver replay fixture allows idle" 0 "$LAST_RC"

# Navigator without READY artifact is nudged instead of idling
setup_session
write_state "craftsman" "navigator" "navigating" "3" "expert" "Review spec before implementation"
run_hook_stdin "enforce-no-idle.sh" '{"teammate_name":"craftsman"}'
assert_exit "H2 navigator without READY blocks" 2 "$LAST_RC"
assert_stderr_contains "H2 navigator without READY message" "READY artifact" "$LAST_STDERR"

# Waiting navigator without published READY is also blocked
setup_session
write_state "craftsman" "navigator" "waiting_on_driver" "3" "expert" "Wait for next checkpoint"
run_hook_stdin "enforce-no-idle.sh" '{"teammate_name":"craftsman"}'
assert_exit "H2 waiting navigator without READY blocks" 2 "$LAST_RC"
assert_stderr_contains "H2 waiting navigator without READY mentions READY" "READY artifact" "$LAST_STDERR"

# Phase 1 (shutdown): .shutdown exists — force-stops
setup_session
touch "$POPCORN/$TEAM/.shutdown"
run_hook_stdin "enforce-no-idle.sh" '{"teammate_name":"craftsman"}'
assert_exit "H2 shutdown allows idle" 0 "$LAST_RC"
assert_stdout_contains "H2 shutdown force-stop JSON" '"continue"' "$LAST_STDOUT"

# Retro pending overrides shutdown: agent must write retro before being stopped
setup_session
touch "$POPCORN/$TEAM/.shutdown"
touch "$POPCORN/$TEAM/.retro-requested"
run_hook_stdin "enforce-no-idle.sh" '{"teammate_name":"craftsman"}'
assert_exit "H2 retro-pending overrides shutdown" 2 "$LAST_RC"
assert_stderr_contains "H2 retro-pending nudge despite shutdown" "Retro time" "$LAST_STDERR"

# Shutdown proceeds after retro is written
setup_session
touch "$POPCORN/$TEAM/.shutdown"
touch "$POPCORN/$TEAM/.retro-requested"
touch "$POPCORN/$TEAM/.retro-craftsman.md"
run_hook_stdin "enforce-no-idle.sh" '{"teammate_name":"craftsman"}'
assert_exit "H2 shutdown after retro done" 0 "$LAST_RC"
assert_stdout_contains "H2 shutdown after retro JSON" '"continue"' "$LAST_STDOUT"

# Shutdown with unresolved OBJECTION — blocks (V11)
setup_session
touch "$POPCORN/$TEAM/.shutdown"
cat >> "$POPCORN/$TEAM/ADVICE.md" <<'EOF'

### OBJECTION OBJ-V11-01 — open
Unresolved at shutdown
EOF
run_hook_stdin "enforce-no-idle.sh" '{"teammate_name":"craftsman"}'
assert_exit "H2 shutdown OBJECTION blocks" 2 "$LAST_RC"
assert_stderr_contains "H2 shutdown OBJECTION message" "OBJECTION" "$LAST_STDERR"
assert_stderr_not_contains "H2 shutdown OBJECTION no JSON" '{"' "$LAST_STDERR"

# Shutdown with resolved OBJECTION — force-stops normally
setup_session
touch "$POPCORN/$TEAM/.shutdown"
cat >> "$POPCORN/$TEAM/ADVICE.md" <<'EOF'

### OBJECTION OBJ-V11-02 — open
Resolved before shutdown

### OBJ-V11-02 — FIXED
Fixed it
EOF
run_hook_stdin "enforce-no-idle.sh" '{"teammate_name":"craftsman"}'
assert_exit "H2 shutdown resolved OBJECTION proceeds" 0 "$LAST_RC"
assert_stdout_contains "H2 shutdown resolved OBJECTION JSON" '"continue"' "$LAST_STDOUT"

# Compaction path: pre/post hooks persist state, idle requires handoff, then retires teammate
setup_session
write_state "craftsman" "driver" "driving" "8" "" "Finish parser fix"
run_hook_stdin "mark-compact-pending.sh" \
  '{"hook_event_name":"PreCompact","trigger":"auto","agent_type":"popcorn-xp:craftsman","transcript_path":"/tmp/compact.jsonl"}'
assert_exit "H2 precompact marker exits 0" 0 "$LAST_RC"
if [ "$(jq -r '.state.phase' "$POPCORN/$TEAM/.compact-pending-craftsman.json" 2>/dev/null || echo missing)" = "driving" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: H2 precompact marker should capture agent state"
fi

run_hook_stdin "record-compact-summary.sh" \
  '{"hook_event_name":"PostCompact","trigger":"auto","compact_summary":"Compacted parser-fix session summary.","agent_type":"popcorn-xp:craftsman"}'
assert_exit "H2 postcompact summary exits 0" 0 "$LAST_RC"
if [ -f "$POPCORN/$TEAM/.compact-stop-craftsman.json" ] && [ ! -f "$POPCORN/$TEAM/.compact-pending-craftsman.json" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: H2 postcompact should create stop marker and clear pending marker"
fi
if grep -q "Compacted parser-fix session summary." "$POPCORN/$TEAM/COMPACTIONS.md" 2>/dev/null; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: H2 postcompact should persist compact summary"
fi

run_hook_stdin "enforce-no-idle.sh" '{"teammate_name":"craftsman"}'
assert_exit "H2 compacted teammate without handoff blocks" 2 "$LAST_RC"
assert_stderr_contains "H2 compacted teammate needs handoff" "context compacted" "$LAST_STDERR"

printf '## Handoff — craftsman\nFresh handoff after compaction\n' > "$POPCORN/$TEAM/handoff-craftsman.md"
run_hook_stdin "enforce-no-idle.sh" '{"teammate_name":"craftsman"}'
assert_exit "H2 compacted teammate with handoff stops" 0 "$LAST_RC"
assert_stdout_contains "H2 compacted teammate stop JSON" '"continue": false' "$LAST_STDOUT"
if [ ! -f "$POPCORN/$TEAM/.compact-stop-craftsman.json" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: H2 compact-stop marker should be cleared after teammate stop"
fi

# AA13: check-rotation.sh no-op without .active-team
rm -rf "$POPCORN"
run_hook_stdin "check-rotation.sh" '{}'
assert_exit "AA13 check-rotation no active-team" 0 "$LAST_RC"
assert_stdout_empty "AA13 check-rotation no stdout" "$LAST_STDOUT"

# AA4: coordinator mode fallback — CLAUDE_CODE_COORDINATOR_MODE set, agent_type unknown → "lead"
setup_session
echo '{}' > "$POPCORN/context-store.json"
COORD_INPUT='{"tool_input":{"file_path":"'"$TMPDIR_ROOT/aa4test.txt"'","offset":null,"limit":null},"tool_response":"content","agent_type":"unknown"}'
env CLAUDE_PROJECT_DIR="$TMPDIR_ROOT" CLAUDE_CODE_COORDINATOR_MODE=1 \
  bash "$HOOKS_DIR/context-store-update-read.sh" <<< "$COORD_INPUT" > /tmp/aa4_stdout 2>/tmp/aa4_stderr || true
AA4_READ_BY=$(jq -r --arg p "$TMPDIR_ROOT/aa4test.txt" '.[$p].read_by' "$POPCORN/context-store.json" 2>/dev/null || echo "MISSING")
if [ "$AA4_READ_BY" = "lead" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: AA4 — coordinator mode should attribute to 'lead', got $AA4_READ_BY"
fi
rm -f /tmp/aa4_stdout /tmp/aa4_stderr "$POPCORN/context-store.json"

# ============================================================
# 8. Multiple open items — correct counting
# ============================================================

echo "--- Multiple items and mixed resolution ---"

setup_session
cat >> "$POPCORN/$TEAM/ADVICE.md" <<'EOF'

### OBJECTION OBJ-5-01 — open
First objection

### OBJECTION OBJ-5-02 — open
Second objection

### OBJ-5-01 — FIXED
Fixed first one
EOF

run_hook "check-advice-on-complete.sh"
assert_exit "mixed: one resolved one not" 2 "$LAST_RC"
assert_stderr_contains "mixed: count is 1" "1 unresolved" "$LAST_STDERR"

# Both resolved — should pass
cat >> "$POPCORN/$TEAM/ADVICE.md" <<'EOF'

### OBJ-5-02 — REJECTED
Rejected second
EOF

run_hook "check-advice-on-complete.sh"
assert_exit "mixed: both resolved" 0 "$LAST_RC"

# ============================================================
# 9. Non-blocking items don't block task completion
# ============================================================

echo "--- Non-blocking advice types ---"

setup_session
cat >> "$POPCORN/$TEAM/ADVICE.md" <<'EOF'

### SMELL SML-6-01 — open
Open smell

### STEER STR-6-01 — open
Open steer

### FYI FYI-6-01 — open
Open FYI
EOF

run_hook "check-advice-on-complete.sh"
assert_exit "non-blocking items don't block" 0 "$LAST_RC"
assert_stdout_contains "non-blocking: mentions SMELL" "SMELL" "$LAST_STDOUT"
assert_stdout_contains "non-blocking: mentions STEER" "STEER" "$LAST_STDOUT"
assert_stdout_contains "non-blocking: mentions FYI" "FYI" "$LAST_STDOUT"

# ============================================================
# 10. Output channel consistency across all scripts
# ============================================================

echo "--- Output channel consistency ---"

# No script should ever output systemMessage
for script in check-advice-on-complete.sh remind-unread-advice.sh remind-checkpoint.sh \
              enforce-no-idle.sh check-objections.sh check-retro-before-delete.sh; do
  if grep -q 'systemMessage' "$HOOKS_DIR/$script"; then
    # Allow in comments only
    if grep 'systemMessage' "$HOOKS_DIR/$script" | grep -vq '^#'; then
      FAIL=$((FAIL + 1))
      ERRORS="${ERRORS}\n  FAIL: $script contains systemMessage in non-comment line"
    else
      PASS=$((PASS + 1))
    fi
  else
    PASS=$((PASS + 1))
  fi
done

# check-rotation.sh uses additionalContext (not systemMessage) — static check
if grep -q 'additionalContext' "$HOOKS_DIR/check-rotation.sh"; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: check-rotation.sh should use additionalContext"
fi

# ============================================================
# 11. R3: edit-event checkpoint enforcement via context-store.log
# ============================================================

echo "--- R3: Edit-event checkpoint enforcement ---"

# No-op when no session
rm -rf "$POPCORN"
run_hook_stdin "context-store-mark-dirty.sh" '{"tool_input":{"file_path":"src/foo.ts"},"agent_type":"popcorn-xp:craftsman"}'
assert_exit "R3 no-op without session" 0 "$LAST_RC"
assert_stdout_empty "R3 no-op stdout" "$LAST_STDOUT"

# Skips .popcorn-xp/ paths
setup_session
run_hook_stdin "context-store-mark-dirty.sh" '{"tool_input":{"file_path":".popcorn-xp/test-team/LOG.md"},"agent_type":"popcorn-xp:craftsman"}'
assert_exit "R3 skip session files" 0 "$LAST_RC"
assert_stdout_empty "R3 skip session files stdout" "$LAST_STDOUT"
if [ ! -f "$POPCORN/context-store.log" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: R3 skip session files should not append to context-store.log"
fi

# First two edits: no additionalContext yet, but event log is created
setup_session
write_state "craftsman" "driver" "driving" "7" "" "Implement hook helper"
run_hook_stdin "context-store-mark-dirty.sh" '{"tool_input":{"file_path":"'"$TMPDIR_ROOT/r3-foo.ts"'"},"agent_type":"popcorn-xp:craftsman"}'
assert_exit "R3 first edit exit 0" 0 "$LAST_RC"
assert_stdout_empty "R3 first edit no context" "$LAST_STDOUT"

run_hook_stdin "context-store-mark-dirty.sh" '{"tool_input":{"file_path":"'"$TMPDIR_ROOT/r3-bar.ts"'"},"agent_type":"popcorn-xp:craftsman"}'
assert_exit "R3 second edit exit 0" 0 "$LAST_RC"
assert_stdout_empty "R3 second edit no context" "$LAST_STDOUT"

# Third edit: injects additionalContext from edit count
run_hook_stdin "context-store-mark-dirty.sh" '{"tool_input":{"file_path":"'"$TMPDIR_ROOT/r3-baz.ts"'"},"agent_type":"popcorn-xp:craftsman"}'
assert_exit "R3 third edit exit 0" 0 "$LAST_RC"
assert_stdout_contains "R3 third edit has context" "additionalContext" "$LAST_STDOUT"
assert_stdout_contains "R3 third edit shows count" "3 file edits" "$LAST_STDOUT"
assert_stdout_not_contains "R3 third edit no systemMessage" "systemMessage" "$LAST_STDOUT"

# Fourth edit: still injects with updated count
run_hook_stdin "context-store-mark-dirty.sh" '{"tool_input":{"file_path":"'"$TMPDIR_ROOT/r3-qux.ts"'"},"agent_type":"popcorn-xp:craftsman"}'
assert_stdout_contains "R3 fourth edit has context" "4 file edits" "$LAST_STDOUT"

# remind-checkpoint.sh derives the same count from context-store.log
run_hook_stdin "remind-checkpoint.sh" '{"teammate_name":"craftsman"}'
assert_exit "R3 remind shows count" 2 "$LAST_RC"
assert_stderr_contains "R3 remind has count" "4 file edit" "$LAST_STDERR"

# ============================================================
# 12. R4: session script subcommands (retro-request, retro, shutdown)
# ============================================================

echo "--- R4: session script subcommands ---"

# Set up a temp session with the real session script
setup_session
cat > "$POPCORN/$TEAM/session" << 'SCRIPT'
#!/bin/bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
STATE_DIR="$DIR/agent-state"
POPCORN_DIR="$(dirname "$DIR")"
mkdir -p "$STATE_DIR"
state_file() { echo "$STATE_DIR/$1.json"; }
checkpoint_cursor_file() { echo "$DIR/.checkpoint-cursor"; }
ensure_state() {
  local file
  file="$(state_file "$1")"
  [ -f "$file" ] || jq -n --arg agent "$1" --arg task_id "${2:-}" --arg updated_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" '{
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
  }' > "$file"
  echo "$file"
}
merge_state() {
  local file tmp
  file="$(ensure_state "$1" "${2:-}")"
  shift 2
  tmp="$file.tmp"
  jq "$@" "$file" > "$tmp" && mv "$tmp" "$file"
}
cmd="${1:-}"; [ -z "$cmd" ] && exit 1; shift
case "$cmd" in
  log) printf '\n### Checkpoint\n%s\n' "$*" >> "$DIR/LOG.md"; if [ -f "$POPCORN_DIR/context-store.log" ]; then wc -l < "$POPCORN_DIR/context-store.log" | tr -d ' ' > "$(checkpoint_cursor_file)"; else echo 0 > "$(checkpoint_cursor_file)"; fi ;;
  advice) T="${1:?}"; ID="${2:?}"; shift 2; grep -q "^### $T $ID" "$DIR/ADVICE.md" 2>/dev/null && exit 0; printf '\n### %s %s — open\n%s\n' "$T" "$ID" "$*" >> "$DIR/ADVICE.md" ;;
  resolve) ID="${1:?}"; O="${2:?}"; shift 2; printf '\n### %s — %s\n%s\n' "$ID" "$O" "${*:-(no detail)}" >> "$DIR/ADVICE.md" ;;
  task) ID="${1:?}"; DRIVER="${2:?}"; NAV="${3:?}"; printf '\n## Task %s — Driver @%s, Navigator @%s\n' "$ID" "$DRIVER" "$NAV" >> "$DIR/LOG.md" ;;
  state) AGENT="${1:?}"; ROLE="${2:?}"; PHASE="${3:?}"; TASK_ID="${4:?}"; BLOCKED_ON="${5:--}"; shift 5
    NEXT_ACTION="${*:--}"
    merge_state "$AGENT" "$TASK_ID" --arg agent "$AGENT" --arg role "$ROLE" --arg phase "$PHASE" --arg task_id "$TASK_ID" \
      --arg blocked_on "$BLOCKED_ON" --arg next_action "$NEXT_ACTION" --arg updated_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
      '.agent = $agent
       | .role = $role
       | .phase = $phase
       | .task_id = $task_id
       | .blocked_on = (if $blocked_on == "-" then "" else $blocked_on end)
       | .next_action = (if $next_action == "-" then "" else $next_action end)
       | .updated_at = $updated_at' ;;
  ready) AGENT="${1:?}"; TASK_ID="${2:?}"; KIND="${3:?}"; shift 3
    DETAIL="${*:?(detail required)}"
    printf '## READY — %s\n\n### Task\n%s\n\n### Artifact Type\n%s\n\n### Notes\n%s\n' "$AGENT" "$TASK_ID" "$KIND" "$DETAIL" > "$DIR/navigator-ready-$AGENT.md"
    merge_state "$AGENT" "$TASK_ID" --arg agent "$AGENT" --arg task_id "$TASK_ID" --arg updated_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
      --arg kind "$KIND" --arg detail "$DETAIL" '.agent = $agent
        | .role = "navigator"
        | .phase = "waiting_on_driver"
        | .task_id = $task_id
        | .blocked_on = "driver checkpoint"
        | .next_action = $detail
        | .navigator_ready = true
        | .navigator_artifact_kind = $kind
        | .navigator_artifact_status = "published"
        | .updated_at = $updated_at'
    printf '\n### Navigator READY\n@%s task %s %s: %s\n' "$AGENT" "$TASK_ID" "$KIND" "$DETAIL" >> "$DIR/LOG.md" ;;
  writeset) AGENT="${1:?}"; TASK_ID="${2:?}"; shift 2
    WRITE_SET="$(printf '%s\n' "$@" | jq -R . | jq -s .)"
    merge_state "$AGENT" "$TASK_ID" --arg task_id "$TASK_ID" --argjson write_set "$WRITE_SET" '.task_id = $task_id | .write_set = $write_set' ;;
  handoff) AGENT="${1:?}"; FILE="$DIR/handoff-$AGENT.md"
    printf '## Handoff — %s\n\n### Role & Task\n\n### What I Was About To Do\n\n### Key Context\n\n### Open Advice\n\n### Recommended Start\n' "$AGENT" > "$FILE"
    echo "Handoff template written to $FILE — fill it out now." ;;
  snapshot) AGENT="${1:?}"; TASK_ID="${2:?}"; FILE="$DIR/snapshot-$AGENT.md"
    printf '## Rotation Snapshot — %s\n\n### Task\n%s\n\n### Files Touched\n\n### Verification Run\n\n### Open Advice\n\n### Next Risk\n\n### Recommended Start\n' "$AGENT" "$TASK_ID" > "$FILE"
    echo "Rotation snapshot template written to $FILE — fill it out before handoff." ;;
  retro-request) touch "$DIR/.retro-requested" ;;
  retro) AGENT="${1:?}"; shift; printf '%s\n' "$*" > "$DIR/.retro-$AGENT.md" ;;
  shutdown) touch "$DIR/.shutdown" ;;
esac
SCRIPT
chmod +x "$POPCORN/$TEAM/session"

SESSION="$POPCORN/$TEAM/session"

# log records checkpoint and advances cursor to current context-store.log line
printf '12:00:00  EDIT       popcorn-xp:craftsman         src/example.ts                           (marked dirty)\n' > "$POPCORN/context-store.log"
"$SESSION" log 'Checkpoint after example edit'
if [ "$(cat "$POPCORN/$TEAM/.checkpoint-cursor" 2>/dev/null || echo missing)" = "1" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: R4 log should update .checkpoint-cursor to current context-store.log line count"
fi

# retro-request creates .retro-requested
"$SESSION" retro-request
if [ -f "$POPCORN/$TEAM/.retro-requested" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: R4 retro-request should create .retro-requested"
fi

# retro creates .retro-{agent}.md with content
"$SESSION" retro craftsman 'Rotation worked well. Advice caught the edge case.'
if [ -f "$POPCORN/$TEAM/.retro-craftsman.md" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: R4 retro should create .retro-craftsman.md"
fi
RETRO_CONTENT=$(cat "$POPCORN/$TEAM/.retro-craftsman.md")
if echo "$RETRO_CONTENT" | grep -q "Rotation worked well"; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: R4 retro file should contain feedback text"
fi

# shutdown creates .shutdown
"$SESSION" shutdown
if [ -f "$POPCORN/$TEAM/.shutdown" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: R4 shutdown should create .shutdown"
fi

# state creates explicit agent state
"$SESSION" state craftsman driver driving 7 - 'Implement hook helper'
STATE_PHASE=$(jq -r '.phase' "$POPCORN/$TEAM/agent-state/craftsman.json" 2>/dev/null || echo "missing")
if [ "$STATE_PHASE" = "driving" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: R4 state should create agent-state/craftsman.json with phase=driving"
fi

# ready creates navigator-ready artifact and waiting state
"$SESSION" ready expert 7 risk_check 'Watch for missing verification on shutdown path.'
if [ -f "$POPCORN/$TEAM/navigator-ready-expert.md" ] && \
   [ "$(jq -r '.navigator_ready' "$POPCORN/$TEAM/agent-state/expert.json" 2>/dev/null || echo false)" = "true" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: R4 ready should create navigator artifact and mark navigator_ready=true"
fi

# writeset records owned files
"$SESSION" writeset craftsman 7 hooks/hooks.json tests/test-hooks.sh
WRITE_COUNT=$(jq -r '.write_set | length' "$POPCORN/$TEAM/agent-state/craftsman.json" 2>/dev/null || echo 0)
if [ "$WRITE_COUNT" = "2" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: R4 writeset should record 2 owned files"
fi

# state merge preserves writeset
"$SESSION" state craftsman driver driving 7 - 'Keep implementing helper'
WRITE_COUNT_AFTER_STATE=$(jq -r '.write_set | length' "$POPCORN/$TEAM/agent-state/craftsman.json" 2>/dev/null || echo 0)
if [ "$WRITE_COUNT_AFTER_STATE" = "2" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: R4 state should preserve existing write_set entries"
fi

# ready + later state merge preserves navigator READY metadata
"$SESSION" writeset expert 7 docs/architecture.md
"$SESSION" ready expert 7 risk_check 'Watch for shutdown path and native agent normalization.'
"$SESSION" state expert navigator waiting_on_driver 7 craftsman 'Wait for the next driver checkpoint'
if [ "$(jq -r '.navigator_ready' "$POPCORN/$TEAM/agent-state/expert.json" 2>/dev/null || echo false)" = "true" ] && \
   [ "$(jq -r '.navigator_artifact_status' "$POPCORN/$TEAM/agent-state/expert.json" 2>/dev/null || echo missing)" = "published" ] && \
   [ "$(jq -r '.write_set | length' "$POPCORN/$TEAM/agent-state/expert.json" 2>/dev/null || echo 0)" = "1" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: R4 ready/state merge should preserve READY metadata and write_set"
fi

# snapshot creates structured handoff template
"$SESSION" snapshot craftsman 7
if [ -f "$POPCORN/$TEAM/snapshot-craftsman.md" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: R4 snapshot should create snapshot-craftsman.md"
fi

# ============================================================
# Context Store tests
# ============================================================

echo "--- Context Store tests ---"

setup_session

# File paths must be within CLAUDE_PROJECT_DIR (V3 boundary check)
CS_FOO="$TMPDIR_ROOT/foo.txt"
CS_BAR="$TMPDIR_ROOT/bar.txt"
CS_BAZ="$TMPDIR_ROOT/baz.txt"
CS_LOCK="$TMPDIR_ROOT/lock.txt"
CS_CLEAN="$TMPDIR_ROOT/clean.txt"
CS_UNKNOWN="$TMPDIR_ROOT/unknown.txt"

# CS1: check returns nothing when store doesn't exist
run_hook_stdin "context-store-check.sh" \
  '{"tool_input":{"file_path":"'"$CS_FOO"'"},"agent_type":"popcorn-xp:scout"}'
assert_exit "CS1: check no store" 0 "$LAST_RC"
assert_stdout_empty "CS1: check no store stdout" "$LAST_STDOUT"

# CS2: update-read creates store and records entry
run_hook_stdin "context-store-update-read.sh" \
  '{"tool_input":{"file_path":"'"$CS_FOO"'","offset":null,"limit":null},"tool_response":"line1\nline2\nline3","agent_type":"popcorn-xp:scout"}'
assert_exit "CS2: update-read creates entry" 0 "$LAST_RC"

# Verify store was created with correct fields
CS_STORE="$POPCORN/context-store.json"
if [ -f "$CS_STORE" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: CS2 — context-store.json not created"
fi

# CS2b: write-set enforcement blocks edits outside ownership
write_state "scout" "driver" "driving" "9" "" "Edit owned file" false "" "" '["'"$CS_FOO"'"]'
run_hook_stdin "context-store-mark-dirty.sh" \
  '{"tool_input":{"file_path":"'"$CS_BAR"'"},"agent_type":"popcorn-xp:scout"}'
assert_exit "CS2b: write-set blocks out-of-scope edit" 2 "$LAST_RC"
assert_stderr_contains "CS2b: write-set message" "outside the declared write set" "$LAST_STDERR"

CS_READ_BY=$(jq -r --arg p "$CS_FOO" '.[$p].read_by' "$CS_STORE" 2>/dev/null || echo "MISSING")
if [ "$CS_READ_BY" = "popcorn-xp:scout" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: CS2 — read_by should be popcorn-xp:scout, got $CS_READ_BY"
fi

CS_DIRTY=$(jq -r --arg p "$CS_FOO" '.[$p].dirty' "$CS_STORE" 2>/dev/null || echo "MISSING")
if [ "$CS_DIRTY" = "false" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: CS2 — dirty should be false after read, got $CS_DIRTY"
fi

CS_PREVIEW_PRESENT=$(jq -r --arg p "$CS_FOO" 'if .[$p] | has("preview") then "yes" else "no" end' "$CS_STORE" 2>/dev/null || echo "MISSING")
if [ "$CS_PREVIEW_PRESENT" = "no" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: CS2 — preview field should not be stored"
fi

# CS3: check returns additionalContext for known clean file
run_hook_stdin "context-store-check.sh" \
  '{"tool_input":{"file_path":"'"$CS_FOO"'"},"agent_type":"popcorn-xp:craftsman"}'
assert_exit "CS3: check clean file" 0 "$LAST_RC"
assert_stdout_contains "CS3: has additionalContext" "additionalContext" "$LAST_STDOUT"
assert_stdout_contains "CS3: mentions reader" "popcorn-xp:scout" "$LAST_STDOUT"
assert_stdout_contains "CS3: says CLEAN" "CLEAN" "$LAST_STDOUT"

# CS4: mark-dirty sets dirty flag and records editor
write_state "craftsman" "driver" "driving" "10" "" "Edit owned file" false "" "" '["'"$CS_FOO"'"]'
run_hook_stdin "context-store-mark-dirty.sh" \
  '{"tool_input":{"file_path":"'"$CS_FOO"'"},"agent_type":"popcorn-xp:craftsman"}'
assert_exit "CS4: mark-dirty" 0 "$LAST_RC"

CS_DIRTY=$(jq -r --arg p "$CS_FOO" '.[$p].dirty' "$CS_STORE" 2>/dev/null || echo "MISSING")
if [ "$CS_DIRTY" = "true" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: CS4 — dirty should be true after edit, got $CS_DIRTY"
fi

CS_EDITED_BY=$(jq -r --arg p "$CS_FOO" '.[$p].edited_by' "$CS_STORE" 2>/dev/null || echo "MISSING")
if [ "$CS_EDITED_BY" = "popcorn-xp:craftsman" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: CS4 — edited_by should be popcorn-xp:craftsman, got $CS_EDITED_BY"
fi

# CS5: check returns DIRTY status with editor name
run_hook_stdin "context-store-check.sh" \
  '{"tool_input":{"file_path":"'"$CS_FOO"'"},"agent_type":"popcorn-xp:expert"}'
assert_exit "CS5: check dirty file" 0 "$LAST_RC"
assert_stdout_contains "CS5: says DIRTY" "DIRTY" "$LAST_STDOUT"
assert_stdout_contains "CS5: mentions editor" "popcorn-xp:craftsman" "$LAST_STDOUT"

# CS6: re-reading clears dirty flag
run_hook_stdin "context-store-update-read.sh" \
  '{"tool_input":{"file_path":"'"$CS_FOO"'","offset":null,"limit":null},"tool_response":"updated content","agent_type":"popcorn-xp:expert"}'
assert_exit "CS6: re-read clears dirty" 0 "$LAST_RC"

CS_DIRTY=$(jq -r --arg p "$CS_FOO" '.[$p].dirty' "$CS_STORE" 2>/dev/null || echo "MISSING")
if [ "$CS_DIRTY" = "false" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: CS6 — dirty should be false after re-read, got $CS_DIRTY"
fi

CS_READ_BY=$(jq -r --arg p "$CS_FOO" '.[$p].read_by' "$CS_STORE" 2>/dev/null || echo "MISSING")
if [ "$CS_READ_BY" = "popcorn-xp:expert" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: CS6 — read_by should update to popcorn-xp:expert, got $CS_READ_BY"
fi

# CS7: editing an unknown in-project file creates a store entry
rm -f "$POPCORN/$TEAM/agent-state/"*.json
run_hook_stdin "context-store-mark-dirty.sh" \
  '{"tool_input":{"file_path":"'"$CS_UNKNOWN"'"},"agent_type":"popcorn-xp:craftsman"}'
assert_exit "CS7: mark-dirty unknown file" 0 "$LAST_RC"
assert_stdout_empty "CS7: no output for unknown file" "$LAST_STDOUT"

CS_HAS_UNKNOWN=$(jq -r --arg p "$CS_UNKNOWN" 'has($p)' "$CS_STORE" 2>/dev/null || echo "false")
if [ "$CS_HAS_UNKNOWN" = "true" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: CS7 — unknown in-project edit should be added to store"
fi

run_hook_stdin "context-store-check.sh" \
  '{"tool_input":{"file_path":"'"$CS_UNKNOWN"'"},"agent_type":"popcorn-xp:expert"}'
assert_exit "CS7b: check edit-only file" 0 "$LAST_RC"
assert_stdout_contains "CS7b: edit-only message" "has not been read through the context store yet" "$LAST_STDOUT"
assert_stdout_contains "CS7b: edit-only still dirty" "DIRTY" "$LAST_STDOUT"
assert_stdout_not_contains "CS7b: no fake unknown reader" "previously read by unknown" "$LAST_STDOUT"

# CS8: popcorn-xp paths are skipped
run_hook_stdin "context-store-update-read.sh" \
  '{"tool_input":{"file_path":"'"$POPCORN/$TEAM/ADVICE.md"'","offset":null,"limit":null},"tool_response":"advice content","agent_type":"popcorn-xp:scout"}'
assert_exit "CS8: skip popcorn paths" 0 "$LAST_RC"

CS_HAS_ADVICE=$(jq -r 'has("'"$POPCORN/$TEAM/ADVICE.md"'")' "$CS_STORE" 2>/dev/null || echo "false")
if [ "$CS_HAS_ADVICE" = "false" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: CS8 — popcorn-xp session files should not be stored"
fi

# CS9: re-read preserves edited_by/edited_at from prior dirty state
# First set up: read, mark dirty, then re-read
rm -f "$POPCORN/$TEAM/agent-state/"*.json
echo '{}' > "$CS_STORE"
run_hook_stdin "context-store-update-read.sh" \
  '{"tool_input":{"file_path":"'"$CS_BAR"'","offset":null,"limit":null},"tool_response":"bar content","agent_type":"popcorn-xp:scout"}'
run_hook_stdin "context-store-mark-dirty.sh" \
  '{"tool_input":{"file_path":"'"$CS_BAR"'"},"agent_type":"popcorn-xp:craftsman"}'
run_hook_stdin "context-store-update-read.sh" \
  '{"tool_input":{"file_path":"'"$CS_BAR"'","offset":null,"limit":null},"tool_response":"bar updated","agent_type":"popcorn-xp:expert"}'

CS_EDITED_BY=$(jq -r --arg p "$CS_BAR" '.[$p].edited_by' "$CS_STORE" 2>/dev/null || echo "MISSING")
if [ "$CS_EDITED_BY" = "popcorn-xp:craftsman" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: CS9 — edited_by should be preserved after re-read, got $CS_EDITED_BY"
fi

# CS10: multiple files in store
run_hook_stdin "context-store-update-read.sh" \
  '{"tool_input":{"file_path":"'"$CS_BAZ"'","offset":null,"limit":null},"tool_response":"baz content","agent_type":"popcorn-xp:tester"}'

CS_COUNT=$(jq 'length' "$CS_STORE" 2>/dev/null || echo "0")
if [ "$CS_COUNT" -ge 2 ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: CS10 — store should have multiple entries, got $CS_COUNT"
fi

# CS11: soft lock — different agent editing a dirty file gets warning
rm -f "$POPCORN/$TEAM/agent-state/"*.json
echo '{}' > "$CS_STORE"
run_hook_stdin "context-store-update-read.sh" \
  '{"tool_input":{"file_path":"'"$CS_LOCK"'","offset":null,"limit":null},"tool_response":"lock content","agent_type":"popcorn-xp:scout"}'
checkpoint_now
run_hook_stdin "context-store-mark-dirty.sh" \
  '{"tool_input":{"file_path":"'"$CS_LOCK"'"},"agent_type":"popcorn-xp:craftsman"}'
assert_exit "CS11a: first edit no lock" 0 "$LAST_RC"
assert_stdout_empty "CS11a: no warning for first editor" "$LAST_STDOUT"

# Now a different agent tries to edit the same file
run_hook_stdin "context-store-mark-dirty.sh" \
  '{"tool_input":{"file_path":"'"$CS_LOCK"'"},"agent_type":"popcorn-xp:expert"}'
assert_exit "CS11b: soft lock allows edit" 0 "$LAST_RC"
assert_stdout_contains "CS11b: soft lock warning" "SOFT LOCK" "$LAST_STDOUT"
assert_stdout_contains "CS11b: mentions active editor" "popcorn-xp:craftsman" "$LAST_STDOUT"

# CS12: soft lock — same agent re-editing gets no warning
checkpoint_now
run_hook_stdin "context-store-mark-dirty.sh" \
  '{"tool_input":{"file_path":"'"$CS_LOCK"'"},"agent_type":"popcorn-xp:expert"}'
assert_exit "CS12: same agent no warning" 0 "$LAST_RC"
assert_stdout_empty "CS12: no soft lock for same agent" "$LAST_STDOUT"

# CS13: soft lock — clean file gets no warning even from different agent
rm -f "$POPCORN/$TEAM/agent-state/"*.json
echo '{}' > "$CS_STORE"
run_hook_stdin "context-store-update-read.sh" \
  '{"tool_input":{"file_path":"'"$CS_CLEAN"'","offset":null,"limit":null},"tool_response":"clean content","agent_type":"popcorn-xp:scout"}'
checkpoint_now
run_hook_stdin "context-store-mark-dirty.sh" \
  '{"tool_input":{"file_path":"'"$CS_CLEAN"'"},"agent_type":"popcorn-xp:craftsman"}'
assert_exit "CS13: first edit on clean file" 0 "$LAST_RC"
assert_stdout_empty "CS13: no warning on clean file" "$LAST_STDOUT"

# CS14: files outside project directory are skipped (V3)
echo '{}' > "$CS_STORE"
run_hook_stdin "context-store-update-read.sh" \
  '{"tool_input":{"file_path":"/tmp/outside.txt","offset":null,"limit":null},"tool_response":"outside content","agent_type":"popcorn-xp:scout"}'
assert_exit "CS14: outside-project read exits 0" 0 "$LAST_RC"
CS_HAS_OUTSIDE=$(jq -r 'has("/tmp/outside.txt")' "$CS_STORE" 2>/dev/null || echo "false")
if [ "$CS_HAS_OUTSIDE" = "false" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: CS14 — files outside project dir should not be stored"
fi

# Clean up context store artifacts
rm -f "$CS_STORE" "$CS_STORE.lock"

# ============================================================
# Context Store Event Log tests
# ============================================================

echo "--- Context Store Event Log tests ---"

setup_session
CS_STORE="$POPCORN/context-store.json"
CS_LOG="$POPCORN/context-store.log"
CS_LOGTEST="$TMPDIR_ROOT/logtest.txt"
rm -f "$CS_LOG"
echo '{}' > "$CS_STORE"

# CL1: update-read logs "new entry" for first read
run_hook_stdin "context-store-update-read.sh" \
  '{"tool_input":{"file_path":"'"$CS_LOGTEST"'","offset":null,"limit":null},"tool_response":"content","agent_type":"popcorn-xp:scout"}'
assert_exit "CL1: update-read exits 0" 0 "$LAST_RC"

if [ -f "$CS_LOG" ] && grep -q "new entry" "$CS_LOG"; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: CL1 — log should contain 'new entry'"
fi

if grep -q "popcorn-xp:scout" "$CS_LOG"; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: CL1 — log should contain agent name"
fi

# CL2: check logs "cache hit, CLEAN" for known clean file
run_hook_stdin "context-store-check.sh" \
  '{"tool_input":{"file_path":"'"$CS_LOGTEST"'"},"agent_type":"popcorn-xp:craftsman"}'

if grep -q "cache hit, CLEAN" "$CS_LOG"; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: CL2 — log should contain 'cache hit, CLEAN'"
fi

# CL3: mark-dirty logs "marked dirty"
run_hook_stdin "context-store-mark-dirty.sh" \
  '{"tool_input":{"file_path":"'"$CS_LOGTEST"'"},"agent_type":"popcorn-xp:craftsman"}'

if grep -q "marked dirty" "$CS_LOG"; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: CL3 — log should contain 'marked dirty'"
fi

# CL4: check logs "cache hit, DIRTY" for dirty file
run_hook_stdin "context-store-check.sh" \
  '{"tool_input":{"file_path":"'"$CS_LOGTEST"'"},"agent_type":"popcorn-xp:expert"}'

if grep -q "cache hit, DIRTY" "$CS_LOG"; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: CL4 — log should contain 'cache hit, DIRTY'"
fi

# CL5: soft lock logs "SOFT LOCK"
run_hook_stdin "context-store-mark-dirty.sh" \
  '{"tool_input":{"file_path":"'"$CS_LOGTEST"'"},"agent_type":"popcorn-xp:expert"}'

if grep -q "SOFT LOCK" "$CS_LOG"; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: CL5 — log should contain 'SOFT LOCK'"
fi

# CL6: re-read logs "updated" (not "new entry")
run_hook_stdin "context-store-update-read.sh" \
  '{"tool_input":{"file_path":"'"$CS_LOGTEST"'","offset":null,"limit":null},"tool_response":"updated content","agent_type":"popcorn-xp:expert"}'

if grep -q "updated" "$CS_LOG"; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: CL6 — log should contain 'updated' for re-read"
fi

# CL7: log entries have timestamps (HH:MM:SS format)
if grep -qE '^[0-9]{2}:[0-9]{2}:[0-9]{2}' "$CS_LOG"; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: CL7 — log entries should have HH:MM:SS timestamps"
fi

# CL8: log has correct number of entries (6 events triggered above)
CL_COUNT=$(wc -l < "$CS_LOG" | tr -d ' ')
if [ "$CL_COUNT" -eq 6 ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: CL8 — expected 6 log entries, got $CL_COUNT"
fi

# Clean up
rm -f "$CS_STORE" "$CS_STORE.lock" "$CS_LOG"

# ============================================================
# Task claim enforcement tests
# ============================================================

echo "--- Task claim: check-task-claim.sh ---"

setup_session

# TC1: no-op when no active session
rm -rf "$POPCORN"
run_hook_stdin "check-task-claim.sh" \
  '{"tool_input":{"taskId":"1","status":"in_progress","owner":"craftsman"},"agent_type":"popcorn-xp:craftsman"}'
assert_exit "TC1: no-op without session" 0 "$LAST_RC"
assert_stdout_empty "TC1: no stdout" "$LAST_STDOUT"

# TC2: non-claim operation (status=completed) passes through
setup_session
run_hook_stdin "check-task-claim.sh" \
  '{"tool_input":{"taskId":"1","status":"completed"},"agent_type":"popcorn-xp:craftsman"}'
assert_exit "TC2: completed status not a claim" 0 "$LAST_RC"

# TC3: description-only update passes through
run_hook_stdin "check-task-claim.sh" \
  '{"tool_input":{"taskId":"1","description":"new desc"},"agent_type":"popcorn-xp:craftsman"}'
assert_exit "TC3: description-only passes" 0 "$LAST_RC"

# TC4: lead (non-popcorn-xp agent_type) passes through even on claim
run_hook_stdin "check-task-claim.sh" \
  '{"tool_input":{"taskId":"1","status":"in_progress"},"agent_type":"unknown"}'
assert_exit "TC4: lead bypass" 0 "$LAST_RC"

run_hook_stdin "check-task-claim.sh" \
  '{"tool_input":{"taskId":"1","status":"in_progress"}}'
assert_exit "TC4b: no agent_type bypass" 0 "$LAST_RC"

# TC5: shutdown guard — blocks claim after .shutdown exists
touch "$POPCORN/$TEAM/.shutdown"
run_hook_stdin "check-task-claim.sh" \
  '{"tool_input":{"taskId":"2","status":"in_progress"},"agent_type":"popcorn-xp:craftsman"}'
assert_exit "TC5: shutdown blocks claim" 2 "$LAST_RC"
assert_stderr_contains "TC5: shutdown message" "shutting down" "$LAST_STDERR"
assert_stderr_not_contains "TC5: no JSON in stderr" '{"' "$LAST_STDERR"
rm -f "$POPCORN/$TEAM/.shutdown"

# TC6: concurrent claim guard — blocks when agent already in registry
setup_session
write_state "craftsman" "driver" "driving" "1" "" "Finish current task"
run_hook_stdin "check-task-claim.sh" \
  '{"tool_input":{"taskId":"2","status":"in_progress"},"agent_type":"popcorn-xp:craftsman"}'
assert_exit "TC6: concurrent claim blocked" 2 "$LAST_RC"
assert_stderr_contains "TC6: mentions current task" "1" "$LAST_STDERR"
assert_stderr_not_contains "TC6: no JSON in stderr" '{"' "$LAST_STDERR"

# TC7: different agent claiming while first agent is busy — should pass
run_hook_stdin "check-task-claim.sh" \
  '{"tool_input":{"taskId":"2","status":"in_progress"},"agent_type":"popcorn-xp:expert"}'
assert_exit "TC7: different agent can claim" 0 "$LAST_RC"

# TC7b: native teammate identifiers are normalized and enforced
write_state "test-engineer" "driver" "driving" "3" "" "Finish native teammate task"
run_hook_stdin "check-task-claim.sh" \
  '{"tool_input":{"taskId":"4","status":"in_progress"},"agent_type":"test-engineer"}'
assert_exit "TC7b: native teammate claim blocked when already busy" 2 "$LAST_RC"
assert_stderr_contains "TC7b: native teammate message mentions current task" "3" "$LAST_STDERR"

# TC8: clean registry — agent can claim
setup_session
run_hook_stdin "check-task-claim.sh" \
  '{"tool_input":{"taskId":"3","status":"in_progress"},"agent_type":"popcorn-xp:craftsman"}'
assert_exit "TC8: clean registry allows claim" 0 "$LAST_RC"

# TC9: replay fixture uses real captured-style stdin
setup_session
run_hook_stdin_file "check-task-claim.sh" "$FIXTURES_DIR/taskupdate-claim-craftsman.json"
assert_exit "TC9: replay fixture claim allowed" 0 "$LAST_RC"

echo "--- Task state tracking: update-task-registry.sh ---"

# TR1: no-op without active session
rm -rf "$POPCORN"
run_hook_stdin "update-task-registry.sh" \
  '{"tool_input":{"taskId":"1","status":"in_progress"},"agent_type":"popcorn-xp:craftsman"}'
assert_exit "TR1: no-op without session" 0 "$LAST_RC"

# TR2: lead updates do not create teammate state
setup_session
run_hook_stdin "update-task-registry.sh" \
  '{"tool_input":{"taskId":"1","status":"in_progress"},"agent_type":"unknown"}'
assert_exit "TR2: non-popcorn-xp agent" 0 "$LAST_RC"
if [ ! -f "$POPCORN/$TEAM/agent-state/unknown.json" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: TR2 — teammate state should not be created for lead updates"
fi

# TR3: in_progress creates driving state
run_hook_stdin "update-task-registry.sh" \
  '{"tool_input":{"taskId":"5","status":"in_progress"},"agent_type":"popcorn-xp:craftsman"}'
assert_exit "TR3: in_progress creates row" 0 "$LAST_RC"
if [ "$(jq -r '.task_id' "$POPCORN/$TEAM/agent-state/craftsman.json" 2>/dev/null || echo missing)" = "5" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: TR3 — claimed task_id not recorded in agent state"
fi
if [ "$(jq -r '.phase' "$POPCORN/$TEAM/agent-state/craftsman.json" 2>/dev/null || echo missing)" = "driving" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: TR3 — in_progress should create explicit driving state"
fi

# TR4: completed transitions to completed state
run_hook_stdin "update-task-registry.sh" \
  '{"tool_input":{"taskId":"5","status":"completed"},"agent_type":"popcorn-xp:craftsman"}'
assert_exit "TR4: completed removes row" 0 "$LAST_RC"
if [ "$(jq -r '.navigator_ready' "$POPCORN/$TEAM/agent-state/craftsman.json" 2>/dev/null || echo true)" = "false" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: TR4 — completed should clear navigator_ready"
fi
if [ "$(jq -r '.phase' "$POPCORN/$TEAM/agent-state/craftsman.json" 2>/dev/null || echo missing)" = "completed" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: TR4 — completed should set explicit completed state"
fi

# TR5: owner-only assignment creates claimed state for native teammate
run_hook_stdin "update-task-registry.sh" \
  '{"tool_input":{"taskId":"6","owner":"tester"},"agent_type":"test-engineer"}'
assert_exit "TR5: owner-only claim recorded" 0 "$LAST_RC"
if [ "$(jq -r '.phase' "$POPCORN/$TEAM/agent-state/test-engineer.json" 2>/dev/null || echo missing)" = "claimed" ] && \
   [ "$(jq -r '.task_id' "$POPCORN/$TEAM/agent-state/test-engineer.json" 2>/dev/null || echo missing)" = "6" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: TR5 — owner-only claim should create claimed state for native teammate"
fi

# TR6: later in_progress for same task upgrades claimed -> driving and preserves writeset
write_state "test-engineer" "driver" "claimed" "6" "" "Start task" false "" "" '["tests/test-hooks.sh"]'
run_hook_stdin "update-task-registry.sh" \
  '{"tool_input":{"taskId":"6","status":"in_progress"},"agent_type":"test-engineer"}'
assert_exit "TR6: claimed upgraded to driving" 0 "$LAST_RC"
if [ "$(jq -r '.phase' "$POPCORN/$TEAM/agent-state/test-engineer.json" 2>/dev/null || echo missing)" = "driving" ] && \
   [ "$(jq -r '.write_set | length' "$POPCORN/$TEAM/agent-state/test-engineer.json" 2>/dev/null || echo 0)" = "1" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: TR6 — in_progress should merge onto existing native teammate state"
fi

# TR7: one agent completion does not affect another agent state
run_hook_stdin "update-task-registry.sh" \
  '{"tool_input":{"taskId":"3","status":"in_progress"},"agent_type":"popcorn-xp:craftsman"}'
run_hook_stdin "update-task-registry.sh" \
  '{"tool_input":{"taskId":"4","status":"in_progress"},"agent_type":"popcorn-xp:expert"}'
run_hook_stdin "update-task-registry.sh" \
  '{"tool_input":{"taskId":"3","status":"completed"},"agent_type":"popcorn-xp:craftsman"}'
if [ "$(jq -r '.task_id' "$POPCORN/$TEAM/agent-state/expert.json" 2>/dev/null || echo missing)" = "4" ] && \
   [ "$(jq -r '.phase' "$POPCORN/$TEAM/agent-state/expert.json" 2>/dev/null || echo missing)" = "driving" ] && \
   [ "$(jq -r '.phase' "$POPCORN/$TEAM/agent-state/craftsman.json" 2>/dev/null || echo missing)" = "completed" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: TR7 — completing craftsman should not affect expert state"
fi

# ============================================================
# Results
# ============================================================

echo ""
echo "=== Results ==="
echo "PASS: $PASS"
echo "FAIL: $FAIL"

if [ "$FAIL" -gt 0 ]; then
  echo ""
  echo "Failures:"
  printf "$ERRORS\n"
  exit 1
else
  echo "All tests passed."
  exit 0
fi
