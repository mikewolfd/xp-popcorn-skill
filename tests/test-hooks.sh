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
HOOKS_DIR="$SCRIPT_DIR/platforms/claude/shared/hooks/scripts"
BIN_DIR="$SCRIPT_DIR/shared/runtime/bin"
FIXTURES_DIR="$SCRIPT_DIR/tests/fixtures"

# Hook scripts live in advice/, team/, or lifecycle/ under HOOKS_DIR
hook_resolve() {
  local script="$1" d
  for d in advice team lifecycle; do
    if [[ -f "$HOOKS_DIR/$d/$script" ]]; then
      echo "$HOOKS_DIR/$d/$script"
      return 0
    fi
  done
  echo "$HOOKS_DIR/$script"
}

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
  local stdout_file stderr_file hp
  hp=$(hook_resolve "$script")
  stdout_file=$(mktemp)
  stderr_file=$(mktemp)
  local rc=0
  env CLAUDE_PROJECT_DIR="$TMPDIR_ROOT" bash "$hp" "$@" \
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
  local stdout_file stderr_file hp
  hp=$(hook_resolve "$script")
  stdout_file=$(mktemp)
  stderr_file=$(mktemp)
  local rc=0
  echo "$stdin_data" | env CLAUDE_PROJECT_DIR="$TMPDIR_ROOT" bash "$hp" "$@" \
    >"$stdout_file" 2>"$stderr_file" || rc=$?
  LAST_STDOUT=$(cat "$stdout_file")
  LAST_STDERR=$(cat "$stderr_file")
  LAST_RC=$rc
  rm -f "$stdout_file" "$stderr_file"
}

run_hook_stdin_file() {
  local script="$1" fixture="$2"
  shift 2
  local stdout_file stderr_file hp
  hp=$(hook_resolve "$script")
  stdout_file=$(mktemp)
  stderr_file=$(mktemp)
  local rc=0
  cat "$fixture" | env CLAUDE_PROJECT_DIR="$TMPDIR_ROOT" bash "$hp" "$@" \
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
  # Tests below exercise team transport (context-store, TaskUpdate, etc.); repo default is subagent when omitted.
  printf '%s\n' team > "$POPCORN/$TEAM/.runtime-mode"
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

for script in check-advice-on-complete.sh enforce-no-idle.sh check-retro-before-delete.sh \
              context-store-check.sh context-store-mark-dirty.sh cleanup-context-store.sh; do
  if [ "$script" = "context-store-check.sh" ] || [ "$script" = "context-store-mark-dirty.sh" ]; then
    run_hook_stdin "$script" '{"tool_input":{"file_path":"/tmp/test.txt"},"agent_type":"popcorn-xp:scout"}'
  else
    run_hook "$script"
  fi
  assert_exit "no-op: $script" 0 "$LAST_RC"
  assert_stdout_empty "no-op stdout: $script" "$LAST_STDOUT"
done

run_hook_stdin "mark-compact-pending.sh" '{"hook_event_name":"PreCompact","trigger":"auto","agent_type":"popcorn-xp:craftsman"}'
assert_exit "no-op: mark-compact-pending.sh" 0 "$LAST_RC"
assert_stdout_empty "no-op stdout: mark-compact-pending.sh" "$LAST_STDOUT"

run_hook_stdin "record-compact-summary.sh" '{"hook_event_name":"PostCompact","trigger":"auto","compact_summary":"summary","agent_type":"popcorn-xp:craftsman"}'
assert_exit "no-op: record-compact-summary.sh" 0 "$LAST_RC"
assert_stdout_empty "no-op stdout: record-compact-summary.sh" "$LAST_STDOUT"

run_hook_stdin "check-advice-on-subagent-stop.sh" '{"hook_event_name":"SubagentStop","agent_type":"Explore"}'
assert_exit "no-op: check-advice-on-subagent-stop.sh" 0 "$LAST_RC"
assert_stdout_empty "no-op stdout: check-advice-on-subagent-stop.sh" "$LAST_STDOUT"

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
echo '12:00:00  EDIT       popcorn-xp:scout             file.txt                                 (marked dirty)' > "$POPCORN/context-store.log"
run_hook "cleanup-context-store.sh"
assert_exit "H5 cleanup context store exits 0" 0 "$LAST_RC"
if [ ! -f "$POPCORN/context-store.log" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: H5 cleanup-context-store should remove context store artifacts"
fi

# ============================================================
# 4. H1: TeammateIdle hooks exit 2 when they have content
# ============================================================

echo "--- H1: TeammateIdle exit codes ---"

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

# V56: Retro pending with prefixed teammate_name — must nudge (uses AGENT_SHORT, not raw name)
setup_session
touch "$POPCORN/$TEAM/.retro-requested"
run_hook_stdin "enforce-no-idle.sh" '{"teammate_name":"popcorn-xp:craftsman"}'
assert_exit "H2 retro pending prefixed blocks" 2 "$LAST_RC"
assert_stderr_contains "H2 retro pending prefixed mentions retro" "retro" "$LAST_STDERR"
assert_stderr_contains "H2 retro pending prefixed mentions short name" "craftsman" "$LAST_STDERR"

# V56: Retro done with prefixed teammate_name — retro file uses short name, must allow idle
setup_session
touch "$POPCORN/$TEAM/.retro-requested"
printf 'It went well\n' > "$POPCORN/$TEAM/.retro-craftsman.md"
run_hook_stdin "enforce-no-idle.sh" '{"teammate_name":"popcorn-xp:craftsman"}'
assert_exit "H2 retro done prefixed allows idle" 0 "$LAST_RC"

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

# Phase 1 (shutdown): .shutdown exists — reminds agent to approve shutdown_request from lead
setup_session
touch "$POPCORN/$TEAM/.shutdown"
run_hook_stdin "enforce-no-idle.sh" '{"teammate_name":"craftsman"}'
assert_exit "H2 shutdown blocks" 2 "$LAST_RC"
assert_stderr_contains "H2 shutdown reminder message" "shutdown_request" "$LAST_STDERR"

# Retro pending overrides shutdown: agent must write retro before being stopped
setup_session
touch "$POPCORN/$TEAM/.shutdown"
touch "$POPCORN/$TEAM/.retro-requested"
run_hook_stdin "enforce-no-idle.sh" '{"teammate_name":"craftsman"}'
assert_exit "H2 retro-pending overrides shutdown" 2 "$LAST_RC"
assert_stderr_contains "H2 retro-pending nudge despite shutdown" "Retro time" "$LAST_STDERR"

# Shutdown proceeds after retro is written — still reminds to approve shutdown_request
setup_session
touch "$POPCORN/$TEAM/.shutdown"
touch "$POPCORN/$TEAM/.retro-requested"
touch "$POPCORN/$TEAM/.retro-craftsman.md"
run_hook_stdin "enforce-no-idle.sh" '{"teammate_name":"craftsman"}'
assert_exit "H2 shutdown after retro done" 2 "$LAST_RC"
assert_stderr_contains "H2 shutdown after retro reminder" "shutdown_request" "$LAST_STDERR"

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

# Shutdown with resolved OBJECTION — reminds to approve shutdown_request
setup_session
touch "$POPCORN/$TEAM/.shutdown"
cat >> "$POPCORN/$TEAM/ADVICE.md" <<'EOF'

### OBJECTION OBJ-V11-02 — open
Resolved before shutdown

### OBJ-V11-02 — FIXED
Fixed it
EOF
run_hook_stdin "enforce-no-idle.sh" '{"teammate_name":"craftsman"}'
assert_exit "H2 shutdown resolved OBJECTION proceeds" 2 "$LAST_RC"
assert_stderr_contains "H2 shutdown resolved OBJECTION reminder" "shutdown_request" "$LAST_STDERR"

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

# AA4: removed — context-store-update-read.sh was deleted in hook rationalization

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
for script in check-advice-on-complete.sh enforce-no-idle.sh check-retro-before-delete.sh; do
  _hpr=$(hook_resolve "$script")
  if grep -q 'systemMessage' "$_hpr"; then
    # Allow in comments only
    if grep 'systemMessage' "$_hpr" | grep -vq '^#'; then
      FAIL=$((FAIL + 1))
      ERRORS="${ERRORS}\n  FAIL: $script contains systemMessage in non-comment line"
    else
      PASS=$((PASS + 1))
    fi
  else
    PASS=$((PASS + 1))
  fi
done

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

# enforce-no-idle.sh (checkpoint check in Phase 5d) derives the same count from context-store.log
run_hook_stdin "enforce-no-idle.sh" '{"teammate_name":"craftsman"}'
assert_exit "R3 enforce checkpoint shows count" 2 "$LAST_RC"
assert_stderr_contains "R3 enforce checkpoint has count" "4 file edit" "$LAST_STDERR"

# ============================================================
# V50: one-driver-at-a-time enforcement in context-store-mark-dirty.sh
# ============================================================
echo "--- V50: one-driver-at-a-time enforcement ---"

# No other driver: edit proceeds normally
setup_session
write_state "craftsman" "driver" "driving" "5" "" "Implement feature"
run_hook_stdin "context-store-mark-dirty.sh" '{"tool_input":{"file_path":"'"$TMPDIR_ROOT/v50-solo.ts"'"},"agent_type":"popcorn-xp:craftsman"}'
assert_exit "V50 solo driver allowed" 0 "$LAST_RC"

# Another agent in phase=driving: block
setup_session
write_state "craftsman" "driver" "driving" "5" "" "Implement feature"
write_state "expert" "driver" "driving" "5" "" "Also driving"
run_hook_stdin "context-store-mark-dirty.sh" '{"tool_input":{"file_path":"'"$TMPDIR_ROOT/v50-conflict.ts"'"},"agent_type":"popcorn-xp:craftsman"}'
assert_exit "V50 concurrent driver blocked" 2 "$LAST_RC"
assert_stderr_contains "V50 concurrent driver names other agent" "expert" "$LAST_STDERR"

# Another agent in phase=completed: allow (non-driving phase does not block)
setup_session
write_state "craftsman" "driver" "driving" "5" "" "Implement feature"
write_state "expert" "driver" "completed" "5" "" "Done"
run_hook_stdin "context-store-mark-dirty.sh" '{"tool_input":{"file_path":"'"$TMPDIR_ROOT/v50-completed.ts"'"},"agent_type":"popcorn-xp:craftsman"}'
assert_exit "V50 completed phase does not block" 0 "$LAST_RC"

# Another agent in phase=bench: allow
setup_session
write_state "craftsman" "driver" "driving" "5" "" "Implement feature"
write_state "expert" "driver" "bench" "-" "" "No tasks"
run_hook_stdin "context-store-mark-dirty.sh" '{"tool_input":{"file_path":"'"$TMPDIR_ROOT/v50-bench.ts"'"},"agent_type":"popcorn-xp:craftsman"}'
assert_exit "V50 bench phase does not block" 0 "$LAST_RC"

# Another agent in phase=handoff_pending: allow
setup_session
write_state "craftsman" "driver" "driving" "5" "" "Implement feature"
write_state "expert" "driver" "handoff_pending" "5" "" "Writing handoff"
run_hook_stdin "context-store-mark-dirty.sh" '{"tool_input":{"file_path":"'"$TMPDIR_ROOT/v50-handoff.ts"'"},"agent_type":"popcorn-xp:craftsman"}'
assert_exit "V50 handoff_pending does not block" 0 "$LAST_RC"

# lead agent is exempt even if another driver is active
setup_session
write_state "craftsman" "driver" "driving" "5" "" "Implement feature"
run_hook_stdin "context-store-mark-dirty.sh" '{"tool_input":{"file_path":"'"$TMPDIR_ROOT/v50-lead.ts"'"},"agent_type":"lead"}'
assert_exit "V50 lead exempt from one-driver guard" 0 "$LAST_RC"

# Navigator editing while another agent drives: block (V80 role guard)
setup_session
write_state "craftsman" "navigator" "waiting_on_driver" "5" "" "Watching driver"
write_state "expert" "driver" "driving" "5" "" "Active driver"
run_hook_stdin "context-store-mark-dirty.sh" '{"tool_input":{"file_path":"'"$TMPDIR_ROOT/v50-nav-edit.ts"'"},"agent_type":"popcorn-xp:craftsman"}'
assert_exit "V50 navigator editing is blocked by role guard" 2 "$LAST_RC"
assert_stderr_contains "V50 navigator edit blocked message" "navigator" "$LAST_STDERR"

# ============================================================
# V61: stale-driver TTL downgrade
# ============================================================
echo "--- V61: stale-driver TTL downgrade ---"

# Stale driver (updated_at > 10 min ago): downgrade hard block to additionalContext warning
setup_session
write_state "craftsman" "driver" "driving" "5" "" "Implement feature"
# Write expert state with an updated_at far in the past (1970 = definitely stale)
jq -n '{agent:"expert",role:"driver",phase:"driving",task_id:"5",blocked_on:"",next_action:"",navigator_ready:false,navigator_artifact_kind:"",navigator_artifact_status:"",write_set:[],updated_at:"2020-01-01T00:00:00Z"}' \
  > "$POPCORN/$TEAM/agent-state/expert.json"
run_hook_stdin "context-store-mark-dirty.sh" \
  '{"tool_input":{"file_path":"'"$TMPDIR_ROOT/v61-stale.ts"'"},"agent_type":"popcorn-xp:craftsman"}'
assert_exit "V61 stale driver allows edit (exit 0)" 0 "$LAST_RC"
assert_stdout_contains "V61 stale driver emits additionalContext" "additionalContext" "$LAST_STDOUT"
assert_stdout_contains "V61 stale driver warning mentions agent" "expert" "$LAST_STDOUT"

# Malformed updated_at: parse fails, conservative fallback keeps hard block
setup_session
write_state "craftsman" "driver" "driving" "5" "" "Implement feature"
jq -n '{agent:"expert",role:"driver",phase:"driving",task_id:"5",blocked_on:"",next_action:"",navigator_ready:false,navigator_artifact_kind:"",navigator_artifact_status:"",write_set:[],updated_at:"not-a-date"}' \
  > "$POPCORN/$TEAM/agent-state/expert.json"
run_hook_stdin "context-store-mark-dirty.sh" \
  '{"tool_input":{"file_path":"'"$TMPDIR_ROOT/v61-malformed.ts"'"},"agent_type":"popcorn-xp:craftsman"}'
assert_exit "V61 malformed updated_at keeps hard block (exit 2)" 2 "$LAST_RC"
assert_stderr_contains "V61 malformed date block message" "already driving" "$LAST_STDERR"

# V69: multiple stale drivers — all warnings accumulated, not overwritten
echo "--- V69: multiple stale drivers accumulated ---"

setup_session
write_state "craftsman" "driver" "driving" "5" "" "Implement feature"
# Two stale drivers (both >10 min old)
jq -n '{agent:"expert",role:"driver",phase:"driving",task_id:"5",blocked_on:"",next_action:"",navigator_ready:false,navigator_artifact_kind:"",navigator_artifact_status:"",write_set:[],updated_at:"2020-01-01T00:00:00Z"}' \
  > "$POPCORN/$TEAM/agent-state/expert.json"
jq -n '{agent:"scout",role:"driver",phase:"driving",task_id:"5",blocked_on:"",next_action:"",navigator_ready:false,navigator_artifact_kind:"",navigator_artifact_status:"",write_set:[],updated_at:"2020-01-01T00:00:00Z"}' \
  > "$POPCORN/$TEAM/agent-state/scout.json"
run_hook_stdin "context-store-mark-dirty.sh" \
  '{"tool_input":{"file_path":"'"$TMPDIR_ROOT/v69-multi-stale.ts"'"},"agent_type":"popcorn-xp:craftsman"}'
assert_exit "V69 multiple stale drivers allows edit (exit 0)" 0 "$LAST_RC"
assert_stdout_contains "V69 stale msg mentions first agent" "expert" "$LAST_STDOUT"
assert_stdout_contains "V69 stale msg mentions second agent" "scout" "$LAST_STDOUT"

# ============================================================
# V45: write set path normalization (relative vs absolute)
# ============================================================
echo "--- V45: write set path normalization ---"

# Relative path in write set matches absolute incoming file_path
setup_session
write_state "craftsman" "driver" "driving" "9" "" "Implement feature" false "" "" '["platforms/claude/shared/hooks/scripts/foo.sh"]'
run_hook_stdin "context-store-mark-dirty.sh" \
  '{"tool_input":{"file_path":"'"$TMPDIR_ROOT/platforms/claude/shared/hooks/scripts/foo.sh"'"},"agent_type":"popcorn-xp:craftsman"}'
assert_exit "V45 relative write set matches absolute path" 0 "$LAST_RC"

# Absolute path in write set still matches absolute incoming path (no regression)
setup_session
write_state "craftsman" "driver" "driving" "9" "" "Implement feature" false "" "" '["'"$TMPDIR_ROOT/platforms/claude/shared/hooks/scripts/bar.sh"'"]'
run_hook_stdin "context-store-mark-dirty.sh" \
  '{"tool_input":{"file_path":"'"$TMPDIR_ROOT/platforms/claude/shared/hooks/scripts/bar.sh"'"},"agent_type":"popcorn-xp:craftsman"}'
assert_exit "V45 absolute write set matches absolute path" 0 "$LAST_RC"

# File not in write set is still blocked
setup_session
write_state "craftsman" "driver" "driving" "9" "" "Implement feature" false "" "" '["platforms/claude/shared/hooks/scripts/foo.sh"]'
run_hook_stdin "context-store-mark-dirty.sh" \
  '{"tool_input":{"file_path":"'"$TMPDIR_ROOT/platforms/claude/shared/hooks/scripts/other.sh"'"},"agent_type":"popcorn-xp:craftsman"}'
assert_exit "V45 file outside write set is blocked" 2 "$LAST_RC"
assert_stderr_contains "V45 outside write set message" "outside the declared write set" "$LAST_STDERR"

# dot-slash prefix in write set matches absolute path (V45-dot-prefix fix)
setup_session
write_state "craftsman" "driver" "driving" "9" "" "Implement feature" false "" "" '["./platforms/claude/shared/hooks/scripts/foo.sh"]'
run_hook_stdin "context-store-mark-dirty.sh" \
  '{"tool_input":{"file_path":"'"$TMPDIR_ROOT/platforms/claude/shared/hooks/scripts/foo.sh"'"},"agent_type":"popcorn-xp:craftsman"}'
assert_exit "V45 dot-slash write set matches absolute path" 0 "$LAST_RC"

# ============================================================
# 11b. Phase 5d: enforce-no-idle.sh checkpoint check (driver with edits)
# ============================================================

# Driver with uncheckpointed edits is blocked
setup_session
write_state "craftsman" "driver" "driving" "2" "" "checkpoint current progress"
run_hook_stdin "context-store-mark-dirty.sh" \
  '{"tool_input":{"file_path":"'"$TMPDIR_ROOT/h2-checkpoint-edit.ts"'"},"agent_type":"popcorn-xp:craftsman"}'
run_hook_stdin "enforce-no-idle.sh" '{"teammate_name":"craftsman"}'
assert_exit "H2 checkpoint driver with edits blocks" 2 "$LAST_RC"
assert_stderr_contains "H2 checkpoint driver edit count" "1 file edit" "$LAST_STDERR"

# Driver with no edits since checkpoint still must enter waiting state
setup_session
write_state "craftsman" "driver" "driving" "2" "" "checkpoint current progress"
echo 0 > "$POPCORN/$TEAM/.checkpoint-cursor"
run_hook_stdin "enforce-no-idle.sh" '{"teammate_name":"craftsman"}'
assert_exit "H2 checkpoint driver no edits still blocked by generic" 2 "$LAST_RC"
assert_stderr_contains "H2 checkpoint driver generic block" "declared state" "$LAST_STDERR"

# Non-driver role skips checkpoint check
setup_session
write_state "craftsman" "navigator" "waiting_on_driver" "2" "" "wait" true "risk_check" "published"
run_hook_stdin "context-store-mark-dirty.sh" \
  '{"tool_input":{"file_path":"'"$TMPDIR_ROOT/h2-nav-edit.ts"'"},"agent_type":"popcorn-xp:craftsman"}'
run_hook_stdin "enforce-no-idle.sh" '{"teammate_name":"craftsman"}'
assert_exit "H2 checkpoint navigator skipped" 0 "$LAST_RC"

# ============================================================
# 11c. Phase 5e: enforce-no-idle.sh advice check (unresolved items)
# ============================================================

# Agent with unresolved advice is blocked
setup_session
write_state "craftsman" "driver" "driving" "5" "" "next task"
cat >> "$POPCORN/$TEAM/ADVICE.md" <<'EOF'

### SMELL SML-H2-01 — open
Something smells during driving
EOF

run_hook_stdin "enforce-no-idle.sh" '{"teammate_name":"craftsman"}'
assert_exit "H2 advice blocks with SMELL" 2 "$LAST_RC"
assert_stderr_contains "H2 advice mentions SMELL" "SMELL" "$LAST_STDERR"

# Multiple unresolved advice items are counted
setup_session
write_state "craftsman" "driver" "driving" "5" "" "next task"
cat >> "$POPCORN/$TEAM/ADVICE.md" <<'EOF'

### OBJECTION OBJ-H2-01 — open
Blocking issue

### STEER STR-H2-01 — open
Direction correction

### FYI FYI-H2-01 — open
Note for later
EOF

run_hook_stdin "enforce-no-idle.sh" '{"teammate_name":"craftsman"}'
assert_exit "H2 advice blocks with multiple items" 2 "$LAST_RC"
assert_stderr_contains "H2 advice shows summary" "1 OBJECTION.*1 STEER.*1 FYI" "$LAST_STDERR"

# Navigator in waiting_on_driver with no OBJECTIONs is allowed
setup_session
write_state "craftsman" "navigator" "waiting_on_driver" "5" "" "wait" true "risk_check" "published"
cat >> "$POPCORN/$TEAM/ADVICE.md" <<'EOF'

### SMELL SML-H2-02 — open
Non-blocking advice

### FYI FYI-H2-02 — open
Just a note
EOF

run_hook_stdin "enforce-no-idle.sh" '{"teammate_name":"craftsman"}'
assert_exit "H2 advice nav waiting allows without OBJ" 0 "$LAST_RC"

# Navigator in waiting_on_driver WITH unresolved OBJECTIONs is blocked
setup_session
write_state "craftsman" "navigator" "waiting_on_driver" "5" "" "wait" true "risk_check" "published"
cat >> "$POPCORN/$TEAM/ADVICE.md" <<'EOF'

### OBJECTION OBJ-H2-02 — open
Blocking issue even for waiting nav

### STEER STR-H2-02 — open
Also blocking
EOF

run_hook_stdin "enforce-no-idle.sh" '{"teammate_name":"craftsman"}'
assert_exit "H2 advice nav waiting blocks on OBJ" 2 "$LAST_RC"
assert_stderr_contains "H2 advice nav blocks message" "unresolved advice" "$LAST_STDERR"

# Completed phase allows idle
setup_session
write_state "craftsman" "driver" "completed" "1" "" ""
run_hook_stdin "enforce-no-idle.sh" '{"teammate_name":"craftsman"}'
assert_exit "H2 completed phase allows idle" 0 "$LAST_RC"

# Debounce: generic catch-all allows through after 3 consecutive nudges
setup_session
# No state file at all — agent has no declared phase
run_hook_stdin "enforce-no-idle.sh" '{"teammate_name":"craftsman"}'
assert_exit "H2 debounce nudge 1 blocks" 2 "$LAST_RC"
run_hook_stdin "enforce-no-idle.sh" '{"teammate_name":"craftsman"}'
assert_exit "H2 debounce nudge 2 blocks" 2 "$LAST_RC"
run_hook_stdin "enforce-no-idle.sh" '{"teammate_name":"craftsman"}'
assert_exit "H2 debounce nudge 3 allows" 0 "$LAST_RC"

# ============================================================
# 12. R4: session script subcommands (retro-request, retro, shutdown)
# ============================================================

echo "--- R4: session script subcommands ---"

# Use shared/runtime/bin/session via CLAUDE_PROJECT_DIR (same mechanism as production)
setup_session
run_session() {
  local stdout_file stderr_file
  stdout_file=$(mktemp)
  stderr_file=$(mktemp)
  local rc=0
  env CLAUDE_PROJECT_DIR="$TMPDIR_ROOT" "$BIN_DIR/session" "$@" \
    >"$stdout_file" 2>"$stderr_file" || rc=$?
  LAST_STDOUT=$(cat "$stdout_file")
  LAST_STDERR=$(cat "$stderr_file")
  LAST_RC=$rc
  rm -f "$stdout_file" "$stderr_file"
}

# log records checkpoint and advances cursor to current context-store.log line
printf '12:00:00  EDIT       popcorn-xp:craftsman         src/example.ts                           (marked dirty)\n' > "$POPCORN/context-store.log"
run_session log 'Checkpoint after example edit'
if [ "$(cat "$POPCORN/$TEAM/.checkpoint-cursor" 2>/dev/null || echo missing)" = "1" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: R4 log should update .checkpoint-cursor to current context-store.log line count"
fi

# retro-request creates .retro-requested
run_session retro-request
if [ -f "$POPCORN/$TEAM/.retro-requested" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: R4 retro-request should create .retro-requested"
fi

# retro creates .retro-{agent}.md with content
run_session retro craftsman 'Rotation worked well. Advice caught the edge case.'
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
run_session shutdown
if [ -f "$POPCORN/$TEAM/.shutdown" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: R4 shutdown should create .shutdown"
fi

# state creates explicit agent state
run_session state craftsman driver driving 7 - 'Implement hook helper'
STATE_PHASE=$(jq -r '.phase' "$POPCORN/$TEAM/agent-state/craftsman.json" 2>/dev/null || echo "missing")
if [ "$STATE_PHASE" = "driving" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: R4 state should create agent-state/craftsman.json with phase=driving"
fi

# ready creates navigator-ready artifact and waiting state
run_session ready expert 7 risk_check 'Watch for missing verification on shutdown path.'
if [ -f "$POPCORN/$TEAM/navigator-ready-expert-T7.md" ] && \
   [ "$(jq -r '.navigator_ready' "$POPCORN/$TEAM/agent-state/expert.json" 2>/dev/null || echo false)" = "true" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: R4 ready should create navigator artifact and mark navigator_ready=true"
fi

# writeset records owned files
run_session writeset craftsman 7 platforms/claude/popcorn-xp-team/hooks/hooks.json tests/test-hooks.sh
WRITE_COUNT=$(jq -r '.write_set | length' "$POPCORN/$TEAM/agent-state/craftsman.json" 2>/dev/null || echo 0)
if [ "$WRITE_COUNT" = "2" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: R4 writeset should record 2 owned files"
fi

# state merge preserves writeset
run_session state craftsman driver driving 7 - 'Keep implementing helper'
WRITE_COUNT_AFTER_STATE=$(jq -r '.write_set | length' "$POPCORN/$TEAM/agent-state/craftsman.json" 2>/dev/null || echo 0)
if [ "$WRITE_COUNT_AFTER_STATE" = "2" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: R4 state should preserve existing write_set entries"
fi

# ready + later state merge preserves navigator READY metadata
run_session writeset expert 7 docs/architecture/architecture.md
run_session ready expert 7 risk_check 'Watch for shutdown path and native agent normalization.'
run_session state expert navigator waiting_on_driver 7 craftsman 'Wait for the next driver checkpoint'
if [ "$(jq -r '.navigator_ready' "$POPCORN/$TEAM/agent-state/expert.json" 2>/dev/null || echo false)" = "true" ] && \
   [ "$(jq -r '.navigator_artifact_status' "$POPCORN/$TEAM/agent-state/expert.json" 2>/dev/null || echo missing)" = "published" ] && \
   [ "$(jq -r '.write_set | length' "$POPCORN/$TEAM/agent-state/expert.json" 2>/dev/null || echo 0)" = "1" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: R4 ready/state merge should preserve READY metadata and write_set"
fi

# task-start creates placeholder, claim, state, and write set in one step
setup_session
printf '%s\n' subagent > "$POPCORN/$TEAM/.runtime-mode"
run_session task-init 8
run_session task-start 8 boyle 'Implement the docs/demo hero' -- docs/demo/index.html docs/demo/styles.css
TASK8_DRIVER=$(jq -r '.driver // ""' "$POPCORN/$TEAM/tasks/T8/meta.json" 2>/dev/null || echo missing)
TASK8_PHASE=$(jq -r '.phase // ""' "$POPCORN/$TEAM/agent-state/boyle.json" 2>/dev/null || echo missing)
TASK8_WRITE_COUNT=$(jq -r '.write_set | length' "$POPCORN/$TEAM/agent-state/boyle.json" 2>/dev/null || echo 0)
if [ "$TASK8_DRIVER" = "boyle" ] && [ "$TASK8_PHASE" = "driving" ] && [ "$TASK8_WRITE_COUNT" = "2" ] && \
   grep -q "## Task T8" "$POPCORN/$TEAM/LOG.md"; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: R4 task-start should atomically establish driver claim, state, write set, and task header"
fi

# snapshot creates structured handoff template
run_session snapshot craftsman 7
if [ -f "$POPCORN/$TEAM/snapshot-craftsman.md" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: R4 snapshot should create snapshot-craftsman.md"
fi

# V72: session advice enforces canonical ID format and type/prefix pairing
echo "--- V72: session advice validation ---"

setup_session
run_session advice OBJECTION O1 'Informal IDs should be rejected'
assert_exit "V72 invalid advice ID blocked" 2 "$LAST_RC"
assert_stderr_contains "V72 invalid advice mentions canonical format" "OBJ-{task}-{seq}" "$LAST_STDERR"
if ! grep -q '^### ' "$POPCORN/$TEAM/ADVICE.md"; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: V72 — invalid advice ID should not append to ADVICE.md"
fi

run_session advice SMELL OBJ-7-01 'Prefix must match the advice type'
assert_exit "V72 mismatched prefix blocked" 2 "$LAST_RC"
assert_stderr_contains "V72 mismatched prefix mentions prefix" "must match" "$LAST_STDERR"

run_session advice FYI FYI-7-01 'Valid advice ID still works'
assert_exit "V72 canonical advice allowed" 0 "$LAST_RC"
if grep -q '^### FYI FYI-7-01 — open' "$POPCORN/$TEAM/ADVICE.md"; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: V72 — canonical advice should append to ADVICE.md"
fi

# V90: session advice records optional author attribution
run_session advice FYI FYI-7-02 alice 'Attributed advice still works'
assert_exit "V90 advice with author allowed" 0 "$LAST_RC"
if grep -qF '### FYI FYI-7-02 — open (by alice)' "$POPCORN/$TEAM/ADVICE.md"; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: V90 — advice author should be recorded in ADVICE.md"
fi

run_session advice FYI FYI-7-03 'Unattributed advice still works'
assert_exit "V90 advice without author allowed" 0 "$LAST_RC"
if grep -qF '### FYI FYI-7-03 — open' "$POPCORN/$TEAM/ADVICE.md"; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: V90 — advice without author should still append to ADVICE.md"
fi

# ============================================================
# Context Store tests
# ============================================================

echo "--- Context Store tests (narrowed to dirty cross-agent reads) ---"

setup_session
CS_LOG="$POPCORN/context-store.log"
CS_FOO="$TMPDIR_ROOT/foo.txt"
CS_FOO_SHORT="${CS_FOO#"$TMPDIR_ROOT/"}"
CS_BAR="$TMPDIR_ROOT/bar.txt"
CS_BAR_SHORT="${CS_BAR#"$TMPDIR_ROOT/"}"

# CS1: check returns nothing when log doesn't exist
rm -f "$CS_LOG"
run_hook_stdin "context-store-check.sh" \
  '{"tool_input":{"file_path":"'"$CS_FOO"'"},"agent_type":"popcorn-xp:scout"}'
assert_exit "CS1: check no log" 0 "$LAST_RC"
assert_stdout_empty "CS1: check no log stdout" "$LAST_STDOUT"

# CS2: check on file with no EDIT in log returns nothing silently
printf '' > "$CS_LOG"
run_hook_stdin "context-store-check.sh" \
  '{"tool_input":{"file_path":"'"$CS_FOO"'"},"agent_type":"popcorn-xp:scout"}'
assert_exit "CS2: check unknown file" 0 "$LAST_RC"
assert_stdout_empty "CS2: check unknown file stdout" "$LAST_STDOUT"

# CS3: check on file with no EDIT (never edited) returns nothing
# Log has a READ event but no EDIT — treated as clean
printf '12:00:00  %-10s %-28s %-40s %s\n' "READ" "popcorn-xp:scout" "$CS_FOO_SHORT" "(read)" > "$CS_LOG"
run_hook_stdin "context-store-check.sh" \
  '{"tool_input":{"file_path":"'"$CS_FOO"'"},"agent_type":"popcorn-xp:craftsman"}'
assert_exit "CS3: check clean file" 0 "$LAST_RC"
assert_stdout_empty "CS3: clean file no output" "$LAST_STDOUT"

# CS4: check on file edited by same agent returns nothing
printf '12:00:01  %-10s %-28s %-40s %s\n' "EDIT" "popcorn-xp:scout" "$CS_FOO_SHORT" "(marked dirty)" >> "$CS_LOG"
run_hook_stdin "context-store-check.sh" \
  '{"tool_input":{"file_path":"'"$CS_FOO"'"},"agent_type":"popcorn-xp:scout"}'
assert_exit "CS4: same agent dirty file" 0 "$LAST_RC"
assert_stdout_empty "CS4: same agent no output" "$LAST_STDOUT"

# CS5: check on file edited by different agent returns additionalContext warning
run_hook_stdin "context-store-check.sh" \
  '{"tool_input":{"file_path":"'"$CS_FOO"'"},"agent_type":"popcorn-xp:craftsman"}'
assert_exit "CS5: different agent dirty file" 0 "$LAST_RC"
assert_stdout_contains "CS5: has additionalContext" "additionalContext" "$LAST_STDOUT"
assert_stdout_contains "CS5: has WARNING" "WARNING" "$LAST_STDOUT"
assert_stdout_contains "CS5: mentions editor" "popcorn-xp:scout" "$LAST_STDOUT"

# CS6: soft lock from mark-dirty (write-side enforcement)
rm -f "$POPCORN/$TEAM/agent-state/"*.json
printf '12:00:01  %-10s %-28s %-40s %s\n' "EDIT" "popcorn-xp:scout" "$CS_BAR_SHORT" "(marked dirty)" > "$CS_LOG"
run_hook_stdin "context-store-mark-dirty.sh" \
  '{"tool_input":{"file_path":"'"$CS_BAR"'"},"agent_type":"popcorn-xp:craftsman"}'
assert_exit "CS6: soft lock on mark-dirty" 0 "$LAST_RC"
assert_stdout_contains "CS6: soft lock warning" "SOFT LOCK" "$LAST_STDOUT"
assert_stdout_contains "CS6: mentions active editor" "popcorn-xp:scout" "$LAST_STDOUT"

# CS7: popcorn-xp session paths are skipped
printf '' > "$CS_LOG"
run_hook_stdin "context-store-check.sh" \
  '{"tool_input":{"file_path":"'"$POPCORN/$TEAM/ADVICE.md"'"},"agent_type":"popcorn-xp:scout"}'
assert_exit "CS7: popcorn paths skipped" 0 "$LAST_RC"
assert_stdout_empty "CS7: popcorn path no output" "$LAST_STDOUT"

# Clean up
rm -f "$CS_LOG"

# ============================================================
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

echo "--- V52: rotation enforcement ---"

# V52-1: No LOG.md — rotation guard is skipped, claim allowed
setup_session
run_hook_stdin "check-task-claim.sh" \
  '{"tool_input":{"taskId":"3","status":"in_progress"},"agent_type":"popcorn-xp:craftsman"}'
assert_exit "V52-1: no LOG.md allows claim" 0 "$LAST_RC"

# V52-2: Agent drove the last task — blocked
setup_session
write_state "craftsman" "driver" "completed" "T1" "" ""
write_state "expert" "navigator" "completed" "T1" "" ""
run_session task-init 1
run_session task T1
run_session task-claim 1 craftsman driver
run_hook_stdin "check-task-claim.sh" \
  '{"tool_input":{"taskId":"3","status":"in_progress"},"agent_type":"popcorn-xp:craftsman"}'
assert_exit "V52-2: consecutive drive blocked" 2 "$LAST_RC"
assert_stderr_contains "V52-2: mentions rotation" "Rotation" "$LAST_STDERR"
assert_stderr_contains "V52-2: names agent" "craftsman" "$LAST_STDERR"

# V52-3: Different agent drove the last task — allowed
setup_session
write_state "craftsman" "driver" "completed" "T1" "" ""
write_state "expert" "driver" "completed" "T1" "" ""
run_session task-init 1
run_session task T1
run_session task-claim 1 expert driver
run_hook_stdin "check-task-claim.sh" \
  '{"tool_input":{"taskId":"3","status":"in_progress"},"agent_type":"popcorn-xp:craftsman"}'
assert_exit "V52-3: rotation satisfied allows claim" 0 "$LAST_RC"

# V52-4: Single teammate state file — rotation exempt
setup_session
write_state "craftsman" "driver" "completed" "" "" ""
run_session task-init 1
run_session task T1
run_session task-claim 1 craftsman driver
run_hook_stdin "check-task-claim.sh" \
  '{"tool_input":{"taskId":"3","status":"in_progress"},"agent_type":"popcorn-xp:craftsman"}'
assert_exit "V52-4: single teammate exempt from rotation" 0 "$LAST_RC"

# V70: nav task claims are exempt from the back-to-back rotation guard
setup_session
write_state "craftsman" "driver" "completed" "T2" "" ""
write_state "expert" "navigator" "completed" "T2" "" ""
run_session task-init 2
run_session task T2
run_session task-claim 2 craftsman driver
run_hook_stdin "check-task-claim.sh" \
  '{"tool_input":{"taskId":"T2-nav","status":"in_progress","description":"Navigate T2 — verify the finished drive"},"agent_type":"popcorn-xp:craftsman"}'
assert_exit "V70: nav task claim allowed" 0 "$LAST_RC"
assert_stdout_empty "V70: nav task claim should not emit stdout" "$LAST_STDOUT"

# V86: Prior navigator role does not bypass rotation on a non-nav claim
setup_session
write_state "craftsman" "navigator" "completed" "T2" "" ""
write_state "expert" "navigator" "completed" "T2" "" ""
run_session task-init 2
run_session task T2
run_session task-claim 2 craftsman driver
run_hook_stdin "check-task-claim.sh" \
  '{"tool_input":{"taskId":"99","status":"in_progress"},"agent_type":"popcorn-xp:craftsman"}'
assert_exit "V86: navigator role still blocked on non-nav claim" 2 "$LAST_RC"
assert_stderr_contains "V86: rotation message" "Rotation" "$LAST_STDERR"

# V86b: Driver role is still blocked by rotation guard (no false positive)
setup_session
write_state "craftsman" "driver" "completed" "T2" "" ""
write_state "expert" "navigator" "completed" "T2" "" ""
run_session task-init 2
run_session task T2
run_session task-claim 2 craftsman driver
run_hook_stdin "check-task-claim.sh" \
  '{"tool_input":{"taskId":"99","status":"in_progress"},"agent_type":"popcorn-xp:craftsman"}'
assert_exit "V86b: driver role still blocked by rotation" 2 "$LAST_RC"
assert_stderr_contains "V86b: rotation message" "Rotation" "$LAST_STDERR"

# V86c: Prior advisor role does not bypass rotation on a non-nav claim
setup_session
write_state "craftsman" "advisor" "completed" "T2" "" ""
write_state "expert" "navigator" "completed" "T2" "" ""
run_session task-init 2
run_session task T2
run_session task-claim 2 craftsman driver
run_hook_stdin "check-task-claim.sh" \
  '{"tool_input":{"taskId":"99","status":"in_progress"},"agent_type":"popcorn-xp:craftsman"}'
assert_exit "V86c: advisor role still blocked on non-nav claim" 2 "$LAST_RC"
assert_stderr_contains "V86c: rotation message" "Rotation" "$LAST_STDERR"

# V71: fallback task headers seed the rotation anchor when the current task skipped `session task`
setup_session
write_state "craftsman" "driver" "completed" "T2" "" ""
write_state "expert" "driver" "completed" "T2" "" ""
run_session task-init 2
run_session task T2
run_session task-claim 2 expert driver
run_session log 'Previous work on T2'
run_hook_stdin "check-task-claim.sh" \
  '{"tool_input":{"taskId":"T3","owner":"craftsman"},"agent_type":"popcorn-xp:craftsman"}'
assert_exit "V71: first owner-only claim with older header allowed" 0 "$LAST_RC"
assert_stdout_empty "V71: first owner-only claim with older header stdout" "$LAST_STDOUT"

run_hook_stdin "update-task-state.sh" \
  '{"tool_input":{"taskId":"T3","owner":"craftsman"},"agent_type":"popcorn-xp:craftsman"}'
assert_exit "V71: claim state update succeeds" 0 "$LAST_RC"
assert_stdout_empty "V71: claim state update stdout" "$LAST_STDOUT"

if grep -qF "## Task T3 (auto) — Driver @craftsman, Navigator @unknown" "$POPCORN/$TEAM/LOG.md"; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: V71 — fallback task header should be written to LOG.md"
fi

write_state "craftsman" "driver" "completed" "T3" "" ""
run_hook_stdin "check-task-claim.sh" \
  '{"tool_input":{"taskId":"T4","owner":"craftsman"},"agent_type":"popcorn-xp:craftsman"}'
assert_exit "V71: second claim blocked by rotation after fallback header" 2 "$LAST_RC"
assert_stdout_empty "V71: second claim blocked stdout" "$LAST_STDOUT"
assert_stderr_contains "V71: rotation message" "Rotation required" "$LAST_STDERR"

echo "--- Task state tracking: update-task-state.sh ---"

# TR1: no-op without active session
rm -rf "$POPCORN"
run_hook_stdin "update-task-state.sh" \
  '{"tool_input":{"taskId":"1","status":"in_progress"},"agent_type":"popcorn-xp:craftsman"}'
assert_exit "TR1: no-op without session" 0 "$LAST_RC"

# TR2: lead updates do not create teammate state
setup_session
run_hook_stdin "update-task-state.sh" \
  '{"tool_input":{"taskId":"1","status":"in_progress"},"agent_type":"unknown"}'
assert_exit "TR2: non-popcorn-xp agent" 0 "$LAST_RC"
if [ ! -f "$POPCORN/$TEAM/agent-state/unknown.json" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: TR2 — teammate state should not be created for lead updates"
fi

# TR3: in_progress updates driving state (agent must have pre-existing state file from session state)
write_state "craftsman" "driver" "claimed" "5" "" "Starting task"
run_hook_stdin "update-task-state.sh" \
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
run_hook_stdin "update-task-state.sh" \
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

# TR5: owner-only assignment updates claimed state for native teammate (pre-existing state required)
write_state "test-engineer" "driver" "claimed" "5" "" "Waiting for assignment"
run_hook_stdin "update-task-state.sh" \
  '{"tool_input":{"taskId":"6","owner":"tester"},"agent_type":"test-engineer"}'
assert_exit "TR5: owner-only claim recorded" 0 "$LAST_RC"
if [ "$(jq -r '.phase' "$POPCORN/$TEAM/agent-state/test-engineer.json" 2>/dev/null || echo missing)" = "claimed" ] && \
   [ "$(jq -r '.task_id' "$POPCORN/$TEAM/agent-state/test-engineer.json" 2>/dev/null || echo missing)" = "6" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: TR5 — owner-only claim should update claimed state for registered teammate"
fi

# TR6: later in_progress for same task upgrades claimed -> driving and preserves writeset
write_state "test-engineer" "driver" "claimed" "6" "" "Start task" false "" "" '["tests/test-hooks.sh"]'
run_hook_stdin "update-task-state.sh" \
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
# (pre-create both agent state files as they would be from prior session state calls)
write_state "craftsman" "driver" "claimed" "3" "" "Starting task"
write_state "expert" "driver" "claimed" "4" "" "Starting task"
run_hook_stdin "update-task-state.sh" \
  '{"tool_input":{"taskId":"3","status":"in_progress"},"agent_type":"popcorn-xp:craftsman"}'
run_hook_stdin "update-task-state.sh" \
  '{"tool_input":{"taskId":"4","status":"in_progress"},"agent_type":"popcorn-xp:expert"}'
run_hook_stdin "update-task-state.sh" \
  '{"tool_input":{"taskId":"3","status":"completed"},"agent_type":"popcorn-xp:craftsman"}'
if [ "$(jq -r '.task_id' "$POPCORN/$TEAM/agent-state/expert.json" 2>/dev/null || echo missing)" = "4" ] && \
   [ "$(jq -r '.phase' "$POPCORN/$TEAM/agent-state/expert.json" 2>/dev/null || echo missing)" = "driving" ] && \
   [ "$(jq -r '.phase' "$POPCORN/$TEAM/agent-state/craftsman.json" 2>/dev/null || echo missing)" = "completed" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: TR7 — completing craftsman should not affect expert state"
fi

# V68: State not created for agents with no existing state file
echo "--- V68: no state created for unregistered agents ---"

# V68-1: in_progress from agent with no pre-existing state file — no file created
setup_session
run_hook_stdin "update-task-state.sh" \
  '{"tool_input":{"taskId":"9","status":"in_progress"},"agent_type":"popcorn-xp:outsider"}'
assert_exit "V68-1: unregistered agent in_progress exits 0" 0 "$LAST_RC"
if [ ! -f "$POPCORN/$TEAM/agent-state/outsider.json" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: V68-1 — state file should not be created for unregistered agent"
fi

# V68-2: owner-only claim from agent with no pre-existing state file — no file created
setup_session
run_hook_stdin "update-task-state.sh" \
  '{"tool_input":{"taskId":"9","owner":"outsider"},"agent_type":"popcorn-xp:outsider"}'
assert_exit "V68-2: unregistered agent owner-only exits 0" 0 "$LAST_RC"
if [ ! -f "$POPCORN/$TEAM/agent-state/outsider.json" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: V68-2 — state file should not be created for unregistered agent on owner-only claim"
fi

# V68-3: registered agent still gets state created normally
setup_session
write_state "craftsman" "driver" "claimed" "9" "" "Start task"
run_hook_stdin "update-task-state.sh" \
  '{"tool_input":{"taskId":"9","status":"in_progress"},"agent_type":"popcorn-xp:craftsman"}'
assert_exit "V68-3: registered agent in_progress exits 0" 0 "$LAST_RC"
if [ "$(jq -r '.phase' "$POPCORN/$TEAM/agent-state/craftsman.json" 2>/dev/null || echo missing)" = "driving" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: V68-3 — registered agent should still get state updated on in_progress"
fi

# ============================================================
# V32: session ready — per-task filename, no overwrite across tasks
# ============================================================

echo "--- V32: per-task navigator-ready filename ---"

setup_session
run_session ready craftsman 3 risk_check 'Check edge cases in parser.'
if [ -f "$POPCORN/$TEAM/navigator-ready-craftsman-T3.md" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: V32 — ready should create navigator-ready-{agent}-T{task}.md"
fi

# Second ready for different task creates a separate file, does not overwrite first
run_session ready craftsman 5 spec_check 'Check spec coverage for task 5.'
if [ -f "$POPCORN/$TEAM/navigator-ready-craftsman-T5.md" ] && \
   [ -f "$POPCORN/$TEAM/navigator-ready-craftsman-T3.md" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: V32 — ready for task 5 should not overwrite task 3 artifact"
fi

# Verify the contents are distinct
T3_CONTENT=$(cat "$POPCORN/$TEAM/navigator-ready-craftsman-T3.md" 2>/dev/null || echo "")
T5_CONTENT=$(cat "$POPCORN/$TEAM/navigator-ready-craftsman-T5.md" 2>/dev/null || echo "")
if echo "$T3_CONTENT" | grep -q "Check edge cases" && echo "$T5_CONTENT" | grep -q "Check spec coverage"; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: V32 — per-task artifacts should contain their respective notes"
fi

# ============================================================
# V36: enforce-no-idle.sh bench phase allows idle
# ============================================================

echo "--- V36: bench phase allows idle ---"

setup_session
write_state "craftsman" "driver" "bench" "-" "" "no tasks assigned"
run_hook_stdin "enforce-no-idle.sh" '{"teammate_name":"craftsman"}'
assert_exit "V36 bench phase exits 0" 0 "$LAST_RC"

# Bench agent with unresolved advice is still allowed (bench bypasses advice checks)
setup_session
write_state "craftsman" "driver" "bench" "-" "" "no tasks assigned"
cat >> "$POPCORN/$TEAM/ADVICE.md" <<'EOF'

### SMELL SML-V36-01 — open
Open smell on bench agent
EOF
run_hook_stdin "enforce-no-idle.sh" '{"teammate_name":"craftsman"}'
assert_exit "V36 bench bypasses advice check" 0 "$LAST_RC"

# ============================================================
# V35: shutdown path writes terminal state before force-stop
# ============================================================

echo "--- V35: shutdown writes terminal state ---"

setup_session
write_state "craftsman" "driver" "driving" "3" "" "finish implementation"
touch "$POPCORN/$TEAM/.shutdown"
run_hook_stdin "enforce-no-idle.sh" '{"teammate_name":"craftsman"}'
assert_exit "V35 shutdown exits 2" 2 "$LAST_RC"
assert_stderr_contains "V35 shutdown reminder message" "shutdown_request" "$LAST_STDERR"
STATE_PHASE_V35=$(jq -r '.phase' "$POPCORN/$TEAM/agent-state/craftsman.json" 2>/dev/null || echo "missing")
if [ "$STATE_PHASE_V35" = "shutdown" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: V35 — shutdown path should write phase=shutdown to agent state (got: $STATE_PHASE_V35)"
fi
NEXT_ACTION_V35=$(jq -r '.next_action' "$POPCORN/$TEAM/agent-state/craftsman.json" 2>/dev/null || echo "missing")
if [ -z "$NEXT_ACTION_V35" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: V35 — shutdown path should clear next_action (got: $NEXT_ACTION_V35)"
fi

# ============================================================
# V37: navigator with published READY in waiting_on_driver allows idle
# ============================================================

echo "--- V37: navigator with published READY allows idle ---"

setup_session
write_state "craftsman" "navigator" "waiting_on_driver" "4" "expert" "Wait for checkpoint" true "risk_check" "published"
run_hook_stdin "enforce-no-idle.sh" '{"teammate_name":"craftsman"}'
assert_exit "V37 navigator published READY allows idle" 0 "$LAST_RC"

# Navigator with READY not published is still blocked
setup_session
write_state "craftsman" "navigator" "waiting_on_driver" "4" "expert" "Wait for checkpoint" false "risk_check" ""
run_hook_stdin "enforce-no-idle.sh" '{"teammate_name":"craftsman"}'
assert_exit "V37 navigator unpublished READY blocks" 2 "$LAST_RC"
assert_stderr_contains "V37 unpublished READY message" "READY artifact" "$LAST_STDERR"

# Navigator with ready=true but status!=published is also blocked
setup_session
write_state "craftsman" "navigator" "waiting_on_driver" "4" "expert" "Wait for checkpoint" true "risk_check" "draft"
run_hook_stdin "enforce-no-idle.sh" '{"teammate_name":"craftsman"}'
assert_exit "V37 navigator draft READY blocks" 2 "$LAST_RC"

# ============================================================
# V34: session task-correct appends corrected header to LOG.md
# ============================================================

echo "--- V34: task-correct appends corrected header ---"

setup_session
run_session task-correct 3 craftsman expert
if grep -q "Task T3 — Driver @craftsman, Navigator @expert (corrected)" "$POPCORN/$TEAM/LOG.md"; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: V34 — task-correct should append corrected header to LOG.md"
fi

# Multiple corrections create multiple log entries (append-only)
run_session task-correct 3 expert craftsman
CORRECTION_COUNT=$(grep -c "(corrected)" "$POPCORN/$TEAM/LOG.md" 2>/dev/null || echo 0)
if [ "$CORRECTION_COUNT" = "2" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: V34 — task-correct is append-only; second correction should produce second entry (got $CORRECTION_COUNT)"
fi

# ============================================================
# V62: task-correct + rotation guard interaction
# ============================================================

echo "--- V62: task-correct + rotation guard ---"

# task-correct changes the last driver in LOG.md; rotation guard should respect the corrected entry
setup_session
write_state "craftsman" "driver" "completed" "T1" "" ""
write_state "expert" "navigator" "completed" "T1" "" ""
# Initial log entry: craftsman drove T1
run_session task T1 craftsman expert
# Correction: expert is now the recorded driver
run_session task-correct T1 expert craftsman
# craftsman is no longer the last driver — should be allowed to drive next
run_hook_stdin "check-task-claim.sh" \
  '{"tool_input":{"taskId":"3","status":"in_progress"},"agent_type":"popcorn-xp:craftsman"}'
assert_exit "V62 corrected-out agent can drive next" 0 "$LAST_RC"

# expert is now the last driver per corrected log — should be blocked
setup_session
write_state "craftsman" "driver" "completed" "T1" "" ""
write_state "expert" "driver" "completed" "T1" "" ""
run_session task T1 craftsman expert
run_session task-correct T1 expert craftsman
run_hook_stdin "check-task-claim.sh" \
  '{"tool_input":{"taskId":"3","status":"in_progress"},"agent_type":"popcorn-xp:expert"}'
assert_exit "V62 corrected-to agent blocked from back-to-back drive" 2 "$LAST_RC"
assert_stderr_contains "V62 rotation message mentions agent" "expert" "$LAST_STDERR"

# ============================================================
# V80: role guard — navigators and advisors cannot edit code files
# ============================================================

echo "--- V80: role guard (navigator/advisor edit block) ---"

# V80a: navigator edit blocked
setup_session
write_state "craftsman" "navigator" "waiting_on_driver" "T1" "" "Reviewing"
run_hook_stdin "context-store-mark-dirty.sh" \
  '{"tool_input":{"file_path":"'"$TMPDIR_ROOT/v80-a.ts"'"},"agent_type":"popcorn-xp:craftsman"}'
assert_exit "V80a navigator edit blocked" 2 "$LAST_RC"
assert_stderr_contains "V80a navigator message" "navigator" "$LAST_STDERR"

# V80b: advisor edit blocked
setup_session
write_state "craftsman" "advisor" "navigating" "T1" "" "Advising"
run_hook_stdin "context-store-mark-dirty.sh" \
  '{"tool_input":{"file_path":"'"$TMPDIR_ROOT/v80-b.ts"'"},"agent_type":"popcorn-xp:craftsman"}'
assert_exit "V80b advisor edit blocked" 2 "$LAST_RC"
assert_stderr_contains "V80b advisor message" "advisor" "$LAST_STDERR"

# V80c: driver edit allowed
setup_session
write_state "craftsman" "driver" "driving" "T1" "" "Implementing"
run_hook_stdin "context-store-mark-dirty.sh" \
  '{"tool_input":{"file_path":"'"$TMPDIR_ROOT/v80-c.ts"'"},"agent_type":"popcorn-xp:craftsman"}'
assert_exit "V80c driver edit allowed" 0 "$LAST_RC"

# V80d: .popcorn-xp/ path bypasses role guard (navigator can write session files)
setup_session
write_state "craftsman" "navigator" "waiting_on_driver" "T1" "" "Reviewing"
run_hook_stdin "context-store-mark-dirty.sh" \
  '{"tool_input":{"file_path":"'"$POPCORN/$TEAM/ADVICE.md"'"},"agent_type":"popcorn-xp:craftsman"}'
assert_exit "V80d popcorn path bypasses role guard" 0 "$LAST_RC"

# V80e: lead agent exempt (no role state)
setup_session
run_hook_stdin "context-store-mark-dirty.sh" \
  '{"tool_input":{"file_path":"'"$TMPDIR_ROOT/v80-e.ts"'"},"agent_type":"lead"}'
assert_exit "V80e lead agent exempt" 0 "$LAST_RC"

# V80f: no state file — fail open, allow edit
setup_session
run_hook_stdin "context-store-mark-dirty.sh" \
  '{"tool_input":{"file_path":"'"$TMPDIR_ROOT/v80-f.ts"'"},"agent_type":"popcorn-xp:craftsman"}'
assert_exit "V80f no state file fails open" 0 "$LAST_RC"

# ============================================================
# V81: advisor review cursor
# ============================================================

echo "--- V81: advisor review cursor ---"

# V81a: advisor with unreviewed edits is blocked
setup_session
write_state "craftsman" "advisor" "working" "9" "" "reviewing log"
printf '12:00:00  %-10s %-28s %-40s %s\n' "EDIT" "popcorn-xp:expert" "src/foo.ts" "(marked dirty)" > "$POPCORN/context-store.log"
# No review cursor file — cursor defaults to 0, so 1 EDIT is unreviewed
run_hook_stdin "enforce-no-idle.sh" '{"teammate_name":"craftsman"}'
assert_exit "V81a advisor unreviewed edits blocked" 2 "$LAST_RC"
assert_stderr_contains "V81a advisor message mentions edit count" "1 new edit" "$LAST_STDERR"

# V81b: advisor after running session review is allowed
setup_session
write_state "craftsman" "advisor" "waiting_on_verification" "9" "" "waiting after review"
printf '12:00:00  %-10s %-28s %-40s %s\n' "EDIT" "popcorn-xp:expert" "src/foo.ts" "(marked dirty)" > "$POPCORN/context-store.log"
env CLAUDE_PROJECT_DIR="$TMPDIR_ROOT" bash "$BIN_DIR/session" review craftsman
run_hook_stdin "enforce-no-idle.sh" '{"teammate_name":"craftsman"}'
assert_exit "V81b advisor after review allows idle" 0 "$LAST_RC"

# V81c: driver role does not trigger advisor check
setup_session
write_state "craftsman" "driver" "completed" "9" "" "done"
printf '12:00:00  %-10s %-28s %-40s %s\n' "EDIT" "popcorn-xp:expert" "src/bar.ts" "(marked dirty)" > "$POPCORN/context-store.log"
checkpoint_now
run_hook_stdin "enforce-no-idle.sh" '{"teammate_name":"craftsman"}'
assert_exit "V81c driver not affected by advisor check" 0 "$LAST_RC"

# ============================================================
# V89: session ready preserves existing role (does not hardcode navigator)
# ============================================================

echo "--- V89: session ready preserves advisor role ---"

setup_session
write_state "craftsman" "advisor" "working" "9" "" "reviewing edits"
run_session ready craftsman 9 correctness_review 'Checked invariants and edge cases.'
V89_ROLE=$(jq -r '.role' "$POPCORN/$TEAM/agent-state/craftsman.json" 2>/dev/null || echo missing)
if [ "$V89_ROLE" = "advisor" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: V89 — session ready should preserve advisor role (got: $V89_ROLE)"
fi
V89_PHASE=$(jq -r '.phase' "$POPCORN/$TEAM/agent-state/craftsman.json" 2>/dev/null || echo missing)
if [ "$V89_PHASE" = "waiting_on_driver" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: V89 — session ready should set phase to waiting_on_driver (got: $V89_PHASE)"
fi

# V89b: session ready defaults to navigator when role is empty
setup_session
write_state "craftsman" "" "" "" "" ""
run_session ready craftsman 9 risk_check 'Default role check.'
V89B_ROLE=$(jq -r '.role' "$POPCORN/$TEAM/agent-state/craftsman.json" 2>/dev/null || echo missing)
if [ "$V89B_ROLE" = "navigator" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: V89b — session ready should default to navigator when no role set (got: $V89B_ROLE)"
fi

# V89c: session ready converts a completed driver into navigator for rotation
setup_session
write_state "craftsman" "driver" "completed" "9" "" "handing off"
run_session ready craftsman 9 risk_check 'Handoff to the next driver.'
V89C_ROLE=$(jq -r '.role' "$POPCORN/$TEAM/agent-state/craftsman.json" 2>/dev/null || echo missing)
if [ "$V89C_ROLE" = "navigator" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: V89c — session ready should convert a completed driver to navigator (got: $V89C_ROLE)"
fi

# V89d: rotated navigator cannot edit after publishing READY
run_hook_stdin "context-store-mark-dirty.sh" \
  '{"tool_input":{"file_path":"'"$TMPDIR_ROOT"'/v89d-rotated.ts"},"agent_type":"popcorn-xp:craftsman"}'
assert_exit "V89d: rotated navigator edit blocked" 2 "$LAST_RC"
assert_stderr_contains "V89d: rotated navigator message" "not driver" "$LAST_STDERR"

# ============================================================
# V92: update-task-state.sh preserves role on task completion
# ============================================================

echo "--- V92: update-task-state preserves advisor role on completion ---"

setup_session
write_state "craftsman" "advisor" "working" "9" "" "finishing review"
run_hook_stdin "update-task-state.sh" \
  '{"tool_input":{"taskId":"9","status":"completed"},"agent_type":"popcorn-xp:craftsman"}'
V92_ROLE=$(jq -r '.role' "$POPCORN/$TEAM/agent-state/craftsman.json" 2>/dev/null || echo missing)
if [ "$V92_ROLE" = "advisor" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: V92 — update-task-state should preserve advisor role on completion (got: $V92_ROLE)"
fi
V92_PHASE=$(jq -r '.phase' "$POPCORN/$TEAM/agent-state/craftsman.json" 2>/dev/null || echo missing)
if [ "$V92_PHASE" = "completed" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: V92 — update-task-state should set phase to completed (got: $V92_PHASE)"
fi

# V92b: update-task-state defaults to navigator on completion when role is empty
setup_session
write_state "craftsman" "" "" "" "" ""
run_hook_stdin "update-task-state.sh" \
  '{"tool_input":{"taskId":"9","status":"completed"},"agent_type":"popcorn-xp:craftsman"}'
V92B_ROLE=$(jq -r '.role' "$POPCORN/$TEAM/agent-state/craftsman.json" 2>/dev/null || echo missing)
if [ "$V92B_ROLE" = "navigator" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: V92b — update-task-state should default to navigator when no role set (got: $V92B_ROLE)"
fi

# V92c: update-task-state converts a completed driver into navigator
setup_session
write_state "craftsman" "driver" "driving" "9" "" "finishing task"
run_hook_stdin "update-task-state.sh" \
  '{"tool_input":{"taskId":"9","status":"completed"},"agent_type":"popcorn-xp:craftsman"}'
V92C_ROLE=$(jq -r '.role' "$POPCORN/$TEAM/agent-state/craftsman.json" 2>/dev/null || echo missing)
if [ "$V92C_ROLE" = "navigator" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: V92c — update-task-state should convert a completed driver to navigator (got: $V92C_ROLE)"
fi

# ============================================================
# DM: dual-mode (subagent runtime)
# ============================================================

echo "--- DM: subagent mode hook bypass ---"

# DM-1: TaskUpdate claim hook skipped in subagent mode (claims use session task-claim)
setup_session
printf '%s\n' subagent > "$POPCORN/$TEAM/.runtime-mode"
write_state "craftsman" "driver" "completed" "T1" "" ""
write_state "expert" "navigator" "completed" "T1" "" ""
run_session task-init 1
run_session task T1
run_session task-claim 1 craftsman driver
run_hook_stdin "check-task-claim.sh" \
  '{"tool_input":{"taskId":"3","status":"in_progress"},"agent_type":"popcorn-xp:craftsman"}'
assert_exit "DM-1: subagent skips check-task-claim" 0 "$LAST_RC"

# DM-2: subagent mode — no working-phase TeammateIdle nudges without agent-state (phases 1–4 still run first)
setup_session
printf '%s\n' subagent > "$POPCORN/$TEAM/.runtime-mode"
run_hook_stdin "enforce-no-idle.sh" '{"teammate_name":"craftsman"}'
assert_exit "DM-2: subagent unregistered agent idle OK" 0 "$LAST_RC"
assert_stdout_empty "DM-2: no stdout" "$LAST_STDOUT"

# DM-3: SubagentStop advice gate skipped in team mode (even with open OBJECTION)
setup_session
cat >> "$POPCORN/$TEAM/ADVICE.md" <<'EOF'

### OBJECTION OBJ-9-01 — open
Blocking
EOF
run_hook_stdin "check-advice-on-subagent-stop.sh" '{"hook_event_name":"SubagentStop","agent_type":"Explore"}'
assert_exit "DM-3: team mode skips SubagentStop advice gate" 0 "$LAST_RC"

# DM-4: SubagentStop runs advice gate in subagent mode
setup_session
printf '%s\n' subagent > "$POPCORN/$TEAM/.runtime-mode"
cat >> "$POPCORN/$TEAM/ADVICE.md" <<'EOF'

### OBJECTION OBJ-9-02 — open
Blocking
EOF
run_hook_stdin "check-advice-on-subagent-stop.sh" '{"hook_event_name":"SubagentStop","agent_type":"Explore"}'
assert_exit "DM-4: subagent SubagentStop enforces OBJECTIONs" 2 "$LAST_RC"

echo "--- DM: session task-bus ---"

# DM-5: task-init, chat, cursor, close
setup_session
printf '%s\n' subagent > "$POPCORN/$TEAM/.runtime-mode"
run_session task-init 1
if [ -f "$POPCORN/$TEAM/tasks/T1/meta.json" ] && [ -f "$POPCORN/$TEAM/tasks/T1/back-forth.md" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: DM-5 task-init should create meta.json and back-forth.md"
fi

run_session chat T1 alice note "hello bus"
run_session cursor-ack alice T1 5
DM5_CUR=$(env CLAUDE_PROJECT_DIR="$TMPDIR_ROOT" "$BIN_DIR/session" cursor-get alice T1)
if [ "$DM5_CUR" = "5" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: DM-5 cursor-get expected 5 (got $DM5_CUR)"
fi

run_session mode
if echo "$LAST_STDOUT" | grep -q subagent; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: DM-5 session mode should print subagent"
fi

run_session close-check
assert_exit "DM-5 close-check OK" 0 "$LAST_RC"

printf '# Retro\nl1\nl2\nl3\nl4\nl5\n' > "$POPCORN/$TEAM/RETRO.md"
run_session close
if [ -f "$POPCORN/$TEAM/.closed.json" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: DM-5 session close should write .closed.json"
fi
if [ ! -f "$POPCORN/.active-team" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: DM-5 session close should clear .popcorn-xp/.active-team"
fi

# DM-6: task-claim rotation enforced via session (same as team hook semantics)
setup_session
printf '%s\n' subagent > "$POPCORN/$TEAM/.runtime-mode"
write_state "craftsman" "driver" "completed" "T1" "" ""
write_state "expert" "navigator" "completed" "T1" "" ""
run_session task-init 1
run_session task T1
run_session task-claim 1 craftsman driver
run_session task-init 2
run_session task T2
run_session task-claim 2 craftsman driver
assert_exit "DM-6: consecutive drive blocked by session task-claim" 2 "$LAST_RC"

# DM-7: log in subagent mode does not touch context-store cursor
setup_session
printf '%s\n' subagent > "$POPCORN/$TEAM/.runtime-mode"
printf 'line\n' > "$POPCORN/context-store.log"
run_session log 'subagent checkpoint'
if [ ! -f "$POPCORN/$TEAM/.checkpoint-cursor" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: DM-7 subagent log should not create .checkpoint-cursor"
fi

# DM-8: session health --strict fails on open OBJECTION
setup_session
printf '%s\n' subagent > "$POPCORN/$TEAM/.runtime-mode"
cat >> "$POPCORN/$TEAM/ADVICE.md" <<'EOF'

### OBJECTION OBJ-88-01 — open
Health test
EOF
run_session health --strict
assert_exit "DM-8 health strict fails on OBJECTION" 1 "$LAST_RC"

# DM-9: session health non-strict passes with OBJECTION (report only)
setup_session
printf '%s\n' subagent > "$POPCORN/$TEAM/.runtime-mode"
cat >> "$POPCORN/$TEAM/ADVICE.md" <<'EOF'

### OBJECTION OBJ-88-02 — open
Health test
EOF
run_session health
assert_exit "DM-9 health default passes with OBJECTION listed" 0 "$LAST_RC"
assert_stdout_contains "DM-9 lists OBJECTION" "OBJECTION" "$LAST_STDOUT"

# DM-10: health --strict fails when navigator navigating without READY file
setup_session
printf '%s\n' subagent > "$POPCORN/$TEAM/.runtime-mode"
run_session task-init 1
write_state "expert" "navigator" "navigating" "1" "" "Review" false "" ""
run_session health --strict
assert_exit "DM-10 strict fails missing READY" 1 "$LAST_RC"

# DM-11: health --strict OK when READY file exists
setup_session
printf '%s\n' subagent > "$POPCORN/$TEAM/.runtime-mode"
run_session task-init 1
write_state "expert" "navigator" "navigating" "1" "" "Review" false "" ""
printf 'ready\n' > "$POPCORN/$TEAM/navigator-ready-expert-T1.md"
run_session health --strict
assert_exit "DM-11 strict OK with READY file" 0 "$LAST_RC"

# DM-11b: health --strict fails when driver claim lacks state/write_set
setup_session
printf '%s\n' subagent > "$POPCORN/$TEAM/.runtime-mode"
run_session task-init 1
run_session task-claim 1 boyle driver
run_session health --strict
assert_exit "DM-11b strict fails missing driver state" 1 "$LAST_RC"
assert_stdout_contains "DM-11b mentions missing driver state" "has no agent-state file" "$LAST_STDOUT"

# DM-11c: health --strict fails when driver write_set is empty
setup_session
printf '%s\n' subagent > "$POPCORN/$TEAM/.runtime-mode"
run_session task-init 1
run_session task-claim 1 boyle driver
run_session state boyle driver driving 1 - 'Implement docs/demo'
run_session health --strict
assert_exit "DM-11c strict fails empty driver write_set" 1 "$LAST_RC"
assert_stdout_contains "DM-11c mentions empty write_set" "write_set is empty" "$LAST_STDOUT"

# DM-12: subagent + registered advisor + task chat ahead of review cursor → enforce-no-idle blocks
setup_session
printf '%s\n' subagent > "$POPCORN/$TEAM/.runtime-mode"
run_session task-init 1
run_session chat T1 driver note "needs advisor eyes"
write_state "tester" "advisor" "working" "1" "" "catch up on chat"
run_hook_stdin "enforce-no-idle.sh" '{"teammate_name":"popcorn-xp:tester"}'
assert_exit "DM-12 subagent advisor chat drift blocks idle" 2 "$LAST_RC"
assert_stderr_contains "DM-12 mentions task chat" "back-forth" "$LAST_STDERR"

# DM-13: subagent advisor after session review clears chat drift nudge
setup_session
printf '%s\n' subagent > "$POPCORN/$TEAM/.runtime-mode"
run_session task-init 1
run_session chat T1 driver note "needs advisor eyes"
write_state "tester" "advisor" "working" "1" "" "catch up"
run_session review tester
run_hook_stdin "enforce-no-idle.sh" '{"teammate_name":"popcorn-xp:tester"}'
# May still nudge generic "declare state" (debounce) — must not be subagent chat drift
assert_stderr_not_contains "DM-13 no chat drift after review" "back-forth" "$LAST_STDERR"

# DM-14+15: close-check rejects active task claims; task-abandon clears them
setup_session
printf '%s\n' subagent > "$POPCORN/$TEAM/.runtime-mode"
run_session task-init 1
run_session task-claim 1 bob driver
run_session close-check
assert_exit "DM-14 close-check blocks open task claim" 1 "$LAST_RC"
run_session task-abandon 1 "session end"
run_session close-check
assert_exit "DM-15 close-check OK after task-abandon" 0 "$LAST_RC"

# DM-16+17: retro-requested requires .retro-{agent}.md or substantial handoff
setup_session
printf '%s\n' subagent > "$POPCORN/$TEAM/.runtime-mode"
write_state "craftsman" "driver" "completed" "1" "" "done"
touch "$POPCORN/$TEAM/.retro-requested"
run_session close-check
assert_exit "DM-16 close-check blocks missing retro" 1 "$LAST_RC"
printf 'line one\nline two\n' > "$POPCORN/$TEAM/.retro-craftsman.md"
run_session close-check
assert_exit "DM-17 close-check OK with retro file" 0 "$LAST_RC"

# DM-18+19: compaction stop marker requires handoff file with 5+ lines
setup_session
printf '%s\n' subagent > "$POPCORN/$TEAM/.runtime-mode"
jq -n '{agent:"tester"}' > "$POPCORN/$TEAM/.compact-stop-tester.json"
run_session close-check
assert_exit "DM-18 close-check blocks compact-stop without handoff" 1 "$LAST_RC"
printf '1\n2\n3\n4\n5\n' > "$POPCORN/$TEAM/handoff-tester.md"
run_session close-check
assert_exit "DM-19 close-check OK with handoff after compact-stop" 0 "$LAST_RC"

# DM-20: subagent mode — TeamDelete retro gate skipped (use session close path)
setup_session
printf '%s\n' subagent > "$POPCORN/$TEAM/.runtime-mode"
run_hook "check-retro-before-delete.sh"
assert_exit "DM-20 subagent skips retro-before-delete" 0 "$LAST_RC"

# DM-21: subagent mode — cleanup-context-store does not remove log
setup_session
printf '%s\n' subagent > "$POPCORN/$TEAM/.runtime-mode"
printf 'keep\n' > "$POPCORN/context-store.log"
run_hook "cleanup-context-store.sh"
assert_exit "DM-21 subagent cleanup-context-store no-op" 0 "$LAST_RC"
if grep -q keep "$POPCORN/context-store.log" 2>/dev/null; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: DM-21 context-store.log should remain in subagent mode"
fi

# DM-22: session close runs close-check; --force skips
setup_session
printf '%s\n' subagent > "$POPCORN/$TEAM/.runtime-mode"
cat >> "$POPCORN/$TEAM/ADVICE.md" <<'EOF'

### OBJECTION OBJ-DM-22 — open
Close block
EOF
run_session close
assert_exit "DM-22 close blocked when close-check fails" 1 "$LAST_RC"
run_session close --force
assert_exit "DM-22 close --force succeeds" 0 "$LAST_RC"
if [ -f "$POPCORN/$TEAM/.closed.json" ] && jq -e '.close_check_skipped == true' "$POPCORN/$TEAM/.closed.json" >/dev/null 2>&1; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: DM-22 .closed.json missing or close_check_skipped not true"
fi

# DM-23: task-claim optional expected revision (CAS)
setup_session
printf '%s\n' subagent > "$POPCORN/$TEAM/.runtime-mode"
run_session task-init 1
run_session task-claim 1 alice driver 0
assert_exit "DM-23a first claim OK" 0 "$LAST_RC"
run_session task-claim 1 bob navigator 0
assert_exit "DM-23b stale expected revision rejected" 2 "$LAST_RC"

# DM-24: subagent navigator waiting_on_driver must cursor-ack task chat
setup_session
printf '%s\n' subagent > "$POPCORN/$TEAM/.runtime-mode"
run_session task-init 1
run_session chat T1 driver note "line for nav"
write_state "expert" "navigator" "waiting_on_driver" "1" "" "wait" true "risk_check" "published"
run_hook_stdin "enforce-no-idle.sh" '{"teammate_name":"popcorn-xp:expert"}'
assert_exit "DM-24 nav chat drift blocks" 2 "$LAST_RC"
assert_stderr_contains "DM-24 mentions cursor-ack" "cursor-ack" "$LAST_STDERR"
run_session cursor-ack expert T1 "$(wc -l < "$POPCORN/$TEAM/tasks/T1/back-forth.md" | tr -d ' ')"
run_hook_stdin "enforce-no-idle.sh" '{"teammate_name":"popcorn-xp:expert"}'
assert_exit "DM-24 after ack allows idle" 0 "$LAST_RC"

# DM-25: SubagentStop warns when compact-pending exists (no OBJECTION)
setup_session
printf '%s\n' subagent > "$POPCORN/$TEAM/.runtime-mode"
jq -n '{phase:"driving"}' > "$POPCORN/$TEAM/.compact-pending-Explore.json"
run_hook_stdin "check-advice-on-subagent-stop.sh" '{"hook_event_name":"SubagentStop","agent_type":"Explore"}'
assert_exit "DM-25 SubagentStop compact warn exit 0" 0 "$LAST_RC"
assert_stdout_contains "DM-25 compaction context" "Compaction pending" "$LAST_STDOUT"

# DM-26: task-revision reads meta; events.jsonl receives task_claim and retries are distinct
setup_session
printf '%s\n' subagent > "$POPCORN/$TEAM/.runtime-mode"
run_session task-init 7
run_session task-claim 7 zoe driver
run_session task-claim 7 zoe driver
run_session task-revision 7
if [ "$LAST_STDOUT" = "1" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: DM-26 task-revision expected 1 got ${LAST_STDOUT:-empty}"
fi
if [ -f "$POPCORN/$TEAM/events.jsonl" ] && grep -q '"event":"task_claim"' "$POPCORN/$TEAM/events.jsonl"; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: DM-26 events.jsonl should log task_claim"
fi
if [ -f "$POPCORN/$TEAM/events.jsonl" ] && grep -q '"event":"task_claim_retry"' "$POPCORN/$TEAM/events.jsonl"; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: DM-26 events.jsonl should log task_claim_retry for duplicate claims"
fi

# DM-27: subagent session close requires RETRO.md (≥5 lines); --force skips
setup_session
printf '%s\n' subagent > "$POPCORN/$TEAM/.runtime-mode"
run_session close
assert_exit "DM-27a close fails without RETRO.md" 1 "$LAST_RC"
assert_stderr_contains "DM-27a stderr mentions RETRO.md" "RETRO.md" "$LAST_STDERR"

printf '# R\n1\n2\n3\n' > "$POPCORN/$TEAM/RETRO.md"
run_session close
assert_exit "DM-27b close fails stub RETRO.md" 1 "$LAST_RC"

printf '# R\n1\n2\n3\n4\n5\n' > "$POPCORN/$TEAM/RETRO.md"
run_session close
assert_exit "DM-27c close OK with substantive RETRO.md" 0 "$LAST_RC"

# DM-28: session close truncates repo-level context-store.log
setup_session
printf '%s\n' subagent > "$POPCORN/$TEAM/.runtime-mode"
printf 'stale-edit-line\n' > "$POPCORN/context-store.log"
printf '# R\n1\n2\n3\n4\n5\n' > "$POPCORN/$TEAM/RETRO.md"
run_session close-check
run_session close
if [ ! -s "$POPCORN/context-store.log" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: DM-28 context-store.log should be empty after session close"
fi

# DM-29: .active-team pointing at a closed team is rejected
setup_session
printf '%s\n' subagent > "$POPCORN/$TEAM/.runtime-mode"
printf '# R\n1\n2\n3\n4\n5\n' > "$POPCORN/$TEAM/RETRO.md"
run_session close-check
run_session close
echo "$TEAM" > "$POPCORN/.active-team"
run_session task-init 9
assert_exit "DM-29 task-init blocked when team already closed" 2 "$LAST_RC"
assert_stderr_contains "DM-29 mentions closed" "closed" "$LAST_STDERR"

# DM-30: placeholder session task + task-claim does not false-trigger rotation (different agent may drive the next task after release)
setup_session
printf '%s\n' subagent > "$POPCORN/$TEAM/.runtime-mode"
write_state "craftsman" "driver" "completed" "T1" "" ""
write_state "expert" "navigator" "completed" "T1" "" ""
run_session task-init 1
run_session task T1
run_session task-claim 1 expert driver
run_session task-release 1 expert
run_session task-init 2
run_session task T2
run_session task-claim 2 craftsman driver
assert_exit "DM-30 expert then craftsman drive is allowed" 0 "$LAST_RC"

# DM-31: task-complete updates completing agent agent-state (subagent; mirrors team TaskUpdate terminal transition)
setup_session
printf '%s\n' subagent > "$POPCORN/$TEAM/.runtime-mode"
run_session task-init 5
run_session task T5
run_session task-claim 5 alice driver
run_session state alice driver driving 5 - 'implement feature'
run_session writeset alice 5 docs/foo.txt
printf '# Advice\n\n' > "$POPCORN/$TEAM/ADVICE.md"
run_session task-complete 5 alice done 'all green'
DM31_PHASE=$(jq -r '.phase // ""' "$POPCORN/$TEAM/agent-state/alice.json")
DM31_ROLE=$(jq -r '.role // ""' "$POPCORN/$TEAM/agent-state/alice.json")
DM31_TID=$(jq -r '.task_id // ""' "$POPCORN/$TEAM/agent-state/alice.json")
DM31_WS=$(jq '(.write_set // []) | length' "$POPCORN/$TEAM/agent-state/alice.json")
if [ "$DM31_PHASE" = "completed" ] && [ "$DM31_ROLE" = "navigator" ] && [ -z "$DM31_TID" ] && [ "${DM31_WS:-99}" -eq 0 ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: DM-31 task-complete agent-state (phase=$DM31_PHASE role=$DM31_ROLE task_id=$DM31_TID write_set_len=$DM31_WS)"
fi

# DM-32: task-release moves releasing agent to bench and clears task_id
setup_session
printf '%s\n' subagent > "$POPCORN/$TEAM/.runtime-mode"
run_session task-init 6
run_session task T6
run_session task-claim 6 bob driver
run_session state bob driver driving 6 - 'work in progress'
run_session writeset bob 6 pkg/x.txt
run_session task-release 6 bob
DM32_PHASE=$(jq -r '.phase // ""' "$POPCORN/$TEAM/agent-state/bob.json")
DM32_TID=$(jq -r '.task_id // ""' "$POPCORN/$TEAM/agent-state/bob.json")
if [ "$DM32_PHASE" = "bench" ] && [ -z "$DM32_TID" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: DM-32 task-release agent-state (phase=$DM32_PHASE task_id=$DM32_TID)"
fi

# ============================================================
# CX: Codex hooks
# ============================================================

echo "--- CX: Codex hooks ---"

# Do not set CLAUDE_PROJECT_DIR — the hooks must resolve git root from stdin .cwd (see resolve-project-dir.sh).
run_codex_hook() {
  local script="$1"
  local stdin_json="$2"
  local stdout_file stderr_file rc=0
  stdout_file=$(mktemp)
  stderr_file=$(mktemp)
  echo "$stdin_json" | (unset CLAUDE_PROJECT_DIR; bash "$SCRIPT_DIR/platforms/codex/subagent/hooks/$script") \
    >"$stdout_file" 2>"$stderr_file" || rc=$?
  LAST_STDOUT=$(cat "$stdout_file")
  LAST_STDERR=$(cat "$stderr_file")
  LAST_RC=$rc
  rm -f "$stdout_file" "$stderr_file"
}

# CX-1: SessionStart — no active team → no stdout
rm -rf "$POPCORN"
run_codex_hook "codex-session-start.sh" "$(jq -nc --arg c "$TMPDIR_ROOT" '{cwd:$c,hook_event_name:"SessionStart",source:"startup"}')"
assert_exit "CX-1 session-start no team exit 0" 0 "$LAST_RC"
if [ -z "$LAST_STDOUT" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: CX-1 expected empty stdout"
fi

# CX-2: SessionStart — active team → JSON additionalContext
setup_session
run_codex_hook "codex-session-start.sh" "$(jq -nc --arg c "$TMPDIR_ROOT" '{cwd:$c,hook_event_name:"SessionStart",source:"startup"}')"
assert_exit "CX-2 session-start with team exit 0" 0 "$LAST_RC"
assert_stdout_contains "CX-2 SessionStart JSON" "SessionStart" "$LAST_STDOUT"
assert_stdout_contains "CX-2 mentions team" "$TEAM" "$LAST_STDOUT"

# CX-3: Stop — no team → continue true JSON
rm -rf "$POPCORN"
run_codex_hook "codex-stop-advice.sh" "$(jq -nc --arg c "$TMPDIR_ROOT" '{cwd:$c,hook_event_name:"Stop",turn_id:"t1"}')"
assert_exit "CX-3 stop no team exit 0" 0 "$LAST_RC"
if echo "$LAST_STDOUT" | jq -e '.continue == true' >/dev/null 2>&1; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: CX-3 expected continue:true JSON"
fi

# CX-4: Stop — open OBJECTION → decision block + reason
setup_session
cat >> "$POPCORN/$TEAM/ADVICE.md" <<'EOF'

### OBJECTION OBJ-CX-01 — open
Codex stop gate
EOF
run_codex_hook "codex-stop-advice.sh" "$(jq -nc --arg c "$TMPDIR_ROOT" '{cwd:$c,hook_event_name:"Stop",turn_id:"t2"}')"
assert_exit "CX-4 stop with OBJECTION exit 0" 0 "$LAST_RC"
if echo "$LAST_STDOUT" | jq -e '.decision == "block"' >/dev/null 2>&1; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: CX-4 expected decision:block JSON"
fi

# CX-5: SessionStart finds .popcorn-xp at git root when cwd is a subdirectory
CX5_ROOT=$(mktemp -d)
git -C "$CX5_ROOT" init -q
mkdir -p "$CX5_ROOT/deep/nested"
mkdir -p "$CX5_ROOT/.popcorn-xp/cx5-team"
echo "cx5-team" > "$CX5_ROOT/.popcorn-xp/.active-team"
printf '# Advice\n' > "$CX5_ROOT/.popcorn-xp/cx5-team/ADVICE.md"
run_codex_hook "codex-session-start.sh" "$(jq -nc --arg c "$CX5_ROOT/deep/nested" '{cwd:$c,hook_event_name:"SessionStart",source:"startup"}')"
assert_exit "CX-5 session-start subdir cwd exit 0" 0 "$LAST_RC"
assert_stdout_contains "CX-5 SessionStart finds team" "cx5-team" "$LAST_STDOUT"
assert_stdout_contains "CX-5 context uses repo-root session path" "$CX5_ROOT/shared/runtime/bin/session" "$LAST_STDOUT"
rm -rf "$CX5_ROOT"

# CX-6: Stop shim blocks OBJECTION when cwd is subdirectory of git root
CX6_ROOT=$(mktemp -d)
git -C "$CX6_ROOT" init -q
mkdir -p "$CX6_ROOT/pkg"
mkdir -p "$CX6_ROOT/.popcorn-xp/cx6-team"
echo "cx6-team" > "$CX6_ROOT/.popcorn-xp/.active-team"
printf '# Advice\n' >> "$CX6_ROOT/.popcorn-xp/cx6-team/ADVICE.md"
cat >> "$CX6_ROOT/.popcorn-xp/cx6-team/ADVICE.md" <<'EOF'

### OBJECTION OBJ-CX-06 — open
subdir gate
EOF
run_codex_hook "codex-stop-advice.sh" "$(jq -nc --arg c "$CX6_ROOT/pkg" '{cwd:$c,hook_event_name:"Stop",turn_id:"t3"}')"
assert_exit "CX-6 stop subdir cwd exit 0" 0 "$LAST_RC"
if echo "$LAST_STDOUT" | jq -e '.decision == "block"' >/dev/null 2>&1; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: CX-6 expected decision:block for subdir cwd"
fi
rm -rf "$CX6_ROOT"

# CX-7: vendored Codex bundle entrypoints exist; lead agent does not point at Claude-only skill path
for CX7f in platforms/codex/subagent/skills/popcorn-xp/SKILL.md shared/runtime/lib/resolve-project-dir.sh; do
  if [ -f "$SCRIPT_DIR/$CX7f" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: CX-7 missing $CX7f"
  fi
done
if grep -q 'platforms/claude/popcorn-xp/skills/popcorn-xp/SKILL.md' "$SCRIPT_DIR/platforms/codex/subagent/agents/popcorn-xp-lead.toml" 2>/dev/null; then
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: CX-7 lead.toml should not reference platforms/claude/popcorn-xp/skills/popcorn-xp/SKILL.md"
else
  PASS=$((PASS + 1))
fi

# CX-8: shared/runtime/bin/session resolves .popcorn-xp from git root when run in a subdirectory (no CLAUDE_PROJECT_DIR)
CX8_ROOT=$(mktemp -d)
CX8_OUT=$(mktemp)
CX8_ERR=$(mktemp)
git -C "$CX8_ROOT" init -q
mkdir -p "$CX8_ROOT/sub"
mkdir -p "$CX8_ROOT/.popcorn-xp/cx8-team"
echo "cx8-team" > "$CX8_ROOT/.popcorn-xp/.active-team"
printf '%s\n' subagent > "$CX8_ROOT/.popcorn-xp/cx8-team/.runtime-mode"
printf '# L\n' > "$CX8_ROOT/.popcorn-xp/cx8-team/LOG.md"
printf '# A\n' > "$CX8_ROOT/.popcorn-xp/cx8-team/ADVICE.md"
CX8_RC=0
(
  cd "$CX8_ROOT/sub" || exit 1
  unset CLAUDE_PROJECT_DIR
  "$BIN_DIR/session" mode
) >"$CX8_OUT" 2>"$CX8_ERR" || CX8_RC=$?
CX8_RC=${CX8_RC:-0}
if [ "$CX8_RC" -eq 0 ] && grep -q subagent "$CX8_OUT" 2>/dev/null; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: CX-8 shared/runtime/bin/session from subdir (rc=$CX8_RC out=$(cat "$CX8_OUT" 2>/dev/null))"
fi
rm -rf "$CX8_ROOT"
rm -f "$CX8_OUT" "$CX8_ERR"

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
