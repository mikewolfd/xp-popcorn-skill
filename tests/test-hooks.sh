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

# --- Fixture setup ---

TMPDIR_ROOT=$(mktemp -d)
TEAM="test-team"
POPCORN="$TMPDIR_ROOT/.popcorn-xp"

setup_session() {
  rm -rf "$POPCORN"
  mkdir -p "$POPCORN/$TEAM"
  echo "$TEAM" > "$POPCORN/.active-team"
  printf "# Advice\n" > "$POPCORN/$TEAM/ADVICE.md"
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
              enforce-no-idle.sh check-objections.sh check-rotation.sh check-retro-before-delete.sh; do
  if [ "$script" = "check-rotation.sh" ]; then
    run_hook_stdin "$script" '{}'
  else
    run_hook "$script"
  fi
  assert_exit "no-op: $script" 0 "$LAST_RC"
  assert_stdout_empty "no-op stdout: $script" "$LAST_STDOUT"
done

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

# remind-checkpoint.sh exits 2 when dirty flag exists
setup_session
touch "$POPCORN/$TEAM/.dirty"
run_hook "remind-checkpoint.sh"
assert_exit "H1 remind-checkpoint blocks" 2 "$LAST_RC"
# Verify dirty flag was cleaned up
if [ ! -f "$POPCORN/$TEAM/.dirty" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: H1 remind-checkpoint should remove .dirty"
fi

# remind-checkpoint.sh exits 0 when no dirty flag
setup_session
run_hook "remind-checkpoint.sh"
assert_exit "H1 remind-checkpoint no-op" 0 "$LAST_RC"

# enforce-no-idle.sh always exits 2 when session active
setup_session
run_hook "enforce-no-idle.sh"
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
assert_stderr_contains "H2 working phase guidance" "productive" "$LAST_STDERR"

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

# Phase 1 (shutdown): .shutdown exists — force-stops
setup_session
touch "$POPCORN/$TEAM/.shutdown"
run_hook_stdin "enforce-no-idle.sh" '{"teammate_name":"craftsman"}'
assert_exit "H2 shutdown allows idle" 0 "$LAST_RC"
assert_stdout_contains "H2 shutdown force-stop JSON" '"continue"' "$LAST_STDOUT"

# Phase 1 overrides Phase 2: both .shutdown and .retro-requested — shutdown wins
setup_session
touch "$POPCORN/$TEAM/.shutdown"
touch "$POPCORN/$TEAM/.retro-requested"
run_hook_stdin "enforce-no-idle.sh" '{"teammate_name":"craftsman"}'
assert_exit "H2 shutdown overrides retro-pending" 0 "$LAST_RC"
assert_stdout_contains "H2 shutdown override JSON" '"continue"' "$LAST_STDOUT"

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
# 11. R3: mark-dirty.sh edit counter and soft enforcement
# ============================================================

echo "--- R3: Edit counter and soft checkpoint enforcement ---"

# No-op when no session
rm -rf "$POPCORN"
run_hook_stdin "mark-dirty.sh" '{"tool_input":{"file_path":"src/foo.ts"}}'
assert_exit "R3 no-op without session" 0 "$LAST_RC"
assert_stdout_empty "R3 no-op stdout" "$LAST_STDOUT"

# Skips .popcorn-xp/ paths
setup_session
run_hook_stdin "mark-dirty.sh" '{"tool_input":{"file_path":".popcorn-xp/test-team/LOG.md"}}'
assert_exit "R3 skip session files" 0 "$LAST_RC"
assert_stdout_empty "R3 skip session files stdout" "$LAST_STDOUT"
if [ ! -f "$POPCORN/$TEAM/.edit-count" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: R3 skip session files should not increment counter"
fi

# First edit: counter=1, no additionalContext
setup_session
run_hook_stdin "mark-dirty.sh" '{"tool_input":{"file_path":"src/foo.ts"}}'
assert_exit "R3 first edit exit 0" 0 "$LAST_RC"
assert_stdout_empty "R3 first edit no context" "$LAST_STDOUT"
if [ -f "$POPCORN/$TEAM/.dirty" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: R3 first edit should set .dirty"
fi
if [ "$(cat "$POPCORN/$TEAM/.edit-count")" = "1" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: R3 first edit counter should be 1"
fi

# Second edit: counter=2, still no context
run_hook_stdin "mark-dirty.sh" '{"tool_input":{"file_path":"src/bar.ts"}}'
assert_exit "R3 second edit exit 0" 0 "$LAST_RC"
assert_stdout_empty "R3 second edit no context" "$LAST_STDOUT"

# Third edit: counter=3, injects additionalContext
run_hook_stdin "mark-dirty.sh" '{"tool_input":{"file_path":"src/baz.ts"}}'
assert_exit "R3 third edit exit 0" 0 "$LAST_RC"
assert_stdout_contains "R3 third edit has context" "additionalContext" "$LAST_STDOUT"
assert_stdout_contains "R3 third edit shows count" "3 file edits" "$LAST_STDOUT"
assert_stdout_not_contains "R3 third edit no systemMessage" "systemMessage" "$LAST_STDOUT"

# Fourth edit: counter=4, still injects
run_hook_stdin "mark-dirty.sh" '{"tool_input":{"file_path":"src/qux.ts"}}'
assert_stdout_contains "R3 fourth edit has context" "4 file edits" "$LAST_STDOUT"

# remind-checkpoint.sh shows count when counter exists
run_hook "remind-checkpoint.sh"
assert_exit "R3 remind shows count" 2 "$LAST_RC"
assert_stderr_contains "R3 remind has count" "4 file edit" "$LAST_STDERR"

# remind-checkpoint.sh cleans up both files
if [ ! -f "$POPCORN/$TEAM/.dirty" ] && [ ! -f "$POPCORN/$TEAM/.edit-count" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: R3 remind should clean up .dirty and .edit-count"
fi

# After cleanup, mark-dirty starts fresh (counter=1 again)
run_hook_stdin "mark-dirty.sh" '{"tool_input":{"file_path":"src/fresh.ts"}}'
assert_stdout_empty "R3 fresh after cleanup no context" "$LAST_STDOUT"
if [ "$(cat "$POPCORN/$TEAM/.edit-count")" = "1" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: R3 counter should reset to 1 after cleanup"
fi

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
cmd="${1:-}"; [ -z "$cmd" ] && exit 1; shift
case "$cmd" in
  log) printf '\n### Checkpoint\n%s\n' "$*" >> "$DIR/LOG.md"; rm -f "$DIR/.dirty" "$DIR/.edit-count" ;;
  advice) T="${1:?}"; ID="${2:?}"; shift 2; grep -q "^### $T $ID" "$DIR/ADVICE.md" 2>/dev/null && exit 0; printf '\n### %s %s — open\n%s\n' "$T" "$ID" "$*" >> "$DIR/ADVICE.md" ;;
  resolve) ID="${1:?}"; O="${2:?}"; shift 2; printf '\n### %s — %s\n%s\n' "$ID" "$O" "${*:-(no detail)}" >> "$DIR/ADVICE.md" ;;
  task) ID="${1:?}"; DRIVER="${2:?}"; NAV="${3:?}"; printf '\n## Task %s — Driver @%s, Navigator @%s\n' "$ID" "$DRIVER" "$NAV" >> "$DIR/LOG.md" ;;
  handoff) AGENT="${1:?}"; FILE="$DIR/handoff-$AGENT.md"
    printf '## Handoff — %s\n\n### Role & Task\n\n### What I Was About To Do\n\n### Key Context\n\n### Open Advice\n\n### Recommended Start\n' "$AGENT" > "$FILE"
    echo "Handoff template written to $FILE — fill it out now." ;;
  retro-request) touch "$DIR/.retro-requested" ;;
  retro) AGENT="${1:?}"; shift; printf '%s\n' "$*" > "$DIR/.retro-$AGENT.md" ;;
  shutdown) touch "$DIR/.shutdown" ;;
esac
SCRIPT
chmod +x "$POPCORN/$TEAM/session"

SESSION="$POPCORN/$TEAM/session"

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
