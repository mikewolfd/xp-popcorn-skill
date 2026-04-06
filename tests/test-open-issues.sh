#!/bin/bash
set -euo pipefail

# test-open-issues.sh — Empirical validation of all open backlog issues.
# Runs hook scripts with crafted inputs to prove or disprove each issue.

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOKS_DIR="$SCRIPT_DIR/platforms/claude/shared/hooks/scripts"

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

# --- Test harness (same as test-hooks.sh) ---

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

# --- Fixtures ---

TMPDIR_ROOT=$(mktemp -d)
TEAM="test-team"
POPCORN="$TMPDIR_ROOT/.popcorn-xp"
AGENTS_DIR="$SCRIPT_DIR/platforms/claude/shared/agents"

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
# AA10: lockf removed from context-store hooks
# ============================================================
# Prove: the current context-store hooks do NOT use lockf.

echo "--- AA10: lockf usage in context store scripts ---"

if grep -q 'lockf' "$(hook_resolve context-store-mark-dirty.sh)" || grep -q 'lockf' "$(hook_resolve context-store-check.sh)" || grep -q 'lockf' "$(hook_resolve cleanup-context-store.sh)"; then
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: AA10 — lockf still present in current context-store scripts"
else
  PASS=$((PASS + 1))
  echo "  AA10 proven: current context-store scripts no longer use lockf"
fi

# ============================================================
# R6: check-advice-on-complete.sh doesn't verify confirmation text
# ============================================================
# Prove: resolve an OBJECTION in ADVICE.md, then complete without
# mentioning it — hook passes (no enforcement of confirmation text)

echo "--- R6: OBJECTION resolved but no confirmation in completion ---"

setup_session
cat >> "$POPCORN/$TEAM/ADVICE.md" <<'EOF'

### OBJECTION OBJ-R6-01 — open
Must use flex-column for panel layout

### OBJ-R6-01 — FIXED
resolved it
EOF

# Task completion should PASS even though completion message doesn't mention OBJ-R6-01
run_hook "check-advice-on-complete.sh"
assert_exit "R6: resolved OBJECTION passes without confirmation text" 0 "$LAST_RC"
# The gap: protocol says completion message must include "OBJ-R6-01: FIXED (Panel gets flex-column)"
# but the hook doesn't verify this

# Also verify with an unresolved OBJECTION — hook correctly blocks
setup_session
cat >> "$POPCORN/$TEAM/ADVICE.md" <<'EOF'

### OBJECTION OBJ-R6-02 — open
Unresolved objection
EOF

run_hook "check-advice-on-complete.sh"
assert_exit "R6: unresolved OBJECTION still blocks" 2 "$LAST_RC"

# VERDICT: R6 CONFIRMED — hook checks resolution in ADVICE.md but not confirmation text in completion message

# ============================================================
# AA7: color: magenta not in documented list
# ============================================================

echo "--- AA7: Undocumented color values ---"

MAGENTA_COUNT=0
for agent_file in "$AGENTS_DIR"/*.md; do
  if grep -q '^color: magenta' "$agent_file"; then
    MAGENTA_COUNT=$((MAGENTA_COUNT + 1))
    echo "  AA7: $(basename "$agent_file") uses color: magenta"
  fi
done

if [ "$MAGENTA_COUNT" -gt 0 ]; then
  PASS=$((PASS + 1))
  echo "  AA7 proven: $MAGENTA_COUNT agent(s) use undocumented color 'magenta'"
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: AA7 — no agents use color: magenta (already fixed?)"
fi

# VERDICT: AA7 CONFIRMED — 2 agents use undocumented magenta

# ============================================================
# AA9: Protocol is loaded via skills, not agent-body references
# ============================================================

echo "--- AA9: Protocol references in agent bodies ---"

AA9_COUNT=0
for agent_file in "$AGENTS_DIR"/*.md; do
  if grep -q 'shared/protocol/' "$agent_file"; then
    AA9_COUNT=$((AA9_COUNT + 1))
  fi
done

AA9_SKILLS_COUNT=0
for agent_file in "$AGENTS_DIR"/*.md; do
  if grep -q 'popcorn-xp-protocol' "$agent_file"; then
    AA9_SKILLS_COUNT=$((AA9_SKILLS_COUNT + 1))
  fi
done

if [ "$AA9_COUNT" -eq 0 ] && [ "$AA9_SKILLS_COUNT" -gt 0 ]; then
  PASS=$((PASS + 1))
  echo "  AA9 proven: no agent bodies reference shared protocol docs, and $AA9_SKILLS_COUNT load via skills field"
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: AA9 — shared-protocol-refs=$AA9_COUNT, skills=$AA9_SKILLS_COUNT"
fi

# VERDICT: AA9 CONFIRMED — protocol loading is centralized in skills

# ============================================================
# AA14: CLAUDE_CODE_COORDINATOR_MODE referenced but undocumented
# ============================================================

echo "--- AA14: CLAUDE_CODE_COORDINATOR_MODE references ---"

REF_COUNT=$(grep -rl 'CLAUDE_CODE_COORDINATOR_MODE' "$SCRIPT_DIR" --include='*.md' --include='*.sh' --include='*.json' 2>/dev/null | wc -l || true)
REF_COUNT=$(echo "$REF_COUNT" | tr -d '[:space:]')
[ -z "$REF_COUNT" ] && REF_COUNT=0
OFFICIAL_DOCS_REF=$(grep -rl 'CLAUDE_CODE_COORDINATOR_MODE' "$SCRIPT_DIR/research/official/" 2>/dev/null | wc -l || true)
OFFICIAL_DOCS_REF=$(echo "$OFFICIAL_DOCS_REF" | tr -d '[:space:]')
[ -z "$OFFICIAL_DOCS_REF" ] && OFFICIAL_DOCS_REF=0

if [ "$REF_COUNT" -gt 0 ] && [ "$OFFICIAL_DOCS_REF" -eq 0 ]; then
  PASS=$((PASS + 1))
  echo "  AA14 proven: $REF_COUNT file(s) reference it, 0 in official docs"
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: AA14 — refs=$REF_COUNT, official=$OFFICIAL_DOCS_REF"
fi

# VERDICT: AA14 CONFIRMED — used in project, absent from official docs

# ============================================================
# Results
# ============================================================

echo ""
echo "=== Open Issue Validation Results ==="
echo "PASS: $PASS"
echo "FAIL: $FAIL"

if [ -n "$ERRORS" ]; then
  echo ""
  echo "Errors:"
  printf "$ERRORS\n"
fi

if [ "$FAIL" -eq 0 ]; then
  echo ""
  echo "All open issues validated successfully."
else
  echo ""
  echo "Some validations failed — check errors above."
  exit 1
fi
