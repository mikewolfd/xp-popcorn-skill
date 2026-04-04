#!/bin/bash
set -euo pipefail

# verify-exercise.sh — Post-session assertions for context store exercise.
# Run from the project root after a popcorn-xp session: bash bin/verify-exercise.sh

STORE=".popcorn-xp/context-store.json"
LOG=".popcorn-xp/context-store.log"

PASS=0
FAIL=0

check() {
  local label="$1" condition="$2"
  if eval "$condition"; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== Context Store Verification ==="
echo ""

# --- Store existence ---
echo "--- Store ---"
check "context-store.json exists" "[ -f '$STORE' ]"

if [ ! -f "$STORE" ]; then
  echo ""
  echo "Cannot continue without store. Run a popcorn-xp session first."
  exit 1
fi

# --- File tracking ---
echo ""
echo "--- File Tracking ---"

COUNT=$(jq 'length' "$STORE")
check "At least 3 files tracked (got $COUNT)" "[ '$COUNT' -ge 3 ]"

# Check for expected files (at least some of the demo project files)
SRC_FILES=$(jq '[keys[] | select(contains("src/"))] | length' "$STORE")
check "At least 2 src/ files tracked (got $SRC_FILES)" "[ '$SRC_FILES' -ge 2 ]"

# --- Agent diversity ---
echo ""
echo "--- Agent Diversity ---"

READERS=$(jq '[.[].read_by] | unique' "$STORE")
READER_COUNT=$(echo "$READERS" | jq 'length')
check "At least 2 different agents read files (got $READER_COUNT)" "[ '$READER_COUNT' -ge 2 ]"

UNKNOWN_READERS=$(jq '[.[] | select(.read_by == "unknown")] | length' "$STORE")
check "No unknown readers (got $UNKNOWN_READERS)" "[ '$UNKNOWN_READERS' -eq 0 ]"

# Check for proper agent name format
BAD_NAMES=$(jq '[.[].read_by | select(startswith("popcorn-xp:") | not)] | length' "$STORE")
check "All readers use popcorn-xp:* names (bad: $BAD_NAMES)" "[ '$BAD_NAMES' -eq 0 ]"

# --- Dirty tracking ---
echo ""
echo "--- Dirty Tracking ---"

DIRTY=$(jq '[.[] | select(.dirty == true)] | length' "$STORE")
check "At least 1 file was marked dirty (got $DIRTY)" "[ '$DIRTY' -ge 1 ]"

UNKNOWN_EDITORS=$(jq '[.[] | select(.edited_by == "unknown")] | length' "$STORE")
check "No unknown editors (got $UNKNOWN_EDITORS)" "[ '$UNKNOWN_EDITORS' -eq 0 ]"

# Check that edited_by exists where dirty is true
DIRTY_NO_EDITOR=$(jq '[.[] | select(.dirty == true and (.edited_by == null or .edited_by == ""))] | length' "$STORE")
check "All dirty files have edited_by (missing: $DIRTY_NO_EDITOR)" "[ '$DIRTY_NO_EDITOR' -eq 0 ]"

# --- Store shape ---
echo ""
echo "--- Store Shape ---"

PREVIEW_FIELDS=$(jq '[.[] | select(has("preview"))] | length' "$STORE")
check "No preview fields remain (got $PREVIEW_FIELDS)" "[ '$PREVIEW_FIELDS' -eq 0 ]"

# --- Event log ---
echo ""
echo "--- Event Log ---"

check "context-store.log exists" "[ -f '$LOG' ]"

if [ -f "$LOG" ]; then
  LOG_LINES=$(wc -l < "$LOG" | tr -d ' ')
  check "Log has entries (got $LOG_LINES)" "[ '$LOG_LINES' -ge 1 ]"

  READ_EVENTS=$(grep -c "READ" "$LOG" 2>/dev/null || echo "0")
  check "Log has READ events (got $READ_EVENTS)" "[ '$READ_EVENTS' -ge 1 ]"

  EDIT_EVENTS=$(grep -c "EDIT" "$LOG" 2>/dev/null || echo "0")
  check "Log has EDIT events (got $EDIT_EVENTS)" "[ '$EDIT_EVENTS' -ge 1 ]"

  CACHE_HITS=$(grep -c "cache hit" "$LOG" 2>/dev/null || echo "0")
  check "Log has cache hits (got $CACHE_HITS)" "[ '$CACHE_HITS' -ge 1 ]"

  SOFT_LOCKS=$(grep -c "SOFT LOCK" "$LOG" 2>/dev/null || echo "0")
  echo "  INFO: $SOFT_LOCKS soft lock warnings fired"
fi

# --- Results ---
echo ""
echo "=== Results ==="
echo "PASS: $PASS"
echo "FAIL: $FAIL"

if [ "$FAIL" -gt 0 ]; then
  echo ""
  echo "Some checks failed. Review the store with: bash bin/inspect-store.sh"
  exit 1
else
  echo "All checks passed."
  exit 0
fi
