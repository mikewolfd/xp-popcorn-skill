#!/bin/bash
set -euo pipefail

# auto-log-messages.sh
# PostToolUse hook on SendMessage: auto-populates ADVICE.md and LOG.md
# from message content. Agents send one message — the system handles persistence.
#
# Detects three patterns:
#   1. Advice: message starts with OBJECTION/SMELL/STEER/FYI + ID
#      -> appends to ADVICE.md under ## Open
#   2. Resolution: message starts with "RESOLVE {ID} {OUTCOME}:"
#      -> appends to ADVICE.md under ## Resolved
#   3. Checkpoint: summary starts with "checkpoint:" (case-insensitive)
#      -> appends to LOG.md
#
# No-op when no active popcorn-xp session (.popcorn-xp/ doesn't exist).

POPCORN_DIR="${CLAUDE_PROJECT_DIR:-.}/.popcorn-xp"
[ ! -d "$POPCORN_DIR" ] && exit 0

ADVICE="$POPCORN_DIR/ADVICE.md"
LOG="$POPCORN_DIR/LOG.md"

# Read hook input from stdin
INPUT=$(cat)

# Extract SendMessage fields from tool_input
MESSAGE=$(echo "$INPUT" | jq -r '.tool_input.message // empty' 2>/dev/null)
SUMMARY=$(echo "$INPUT" | jq -r '.tool_input.summary // empty' 2>/dev/null)
TO=$(echo "$INPUT" | jq -r '.tool_input.to // empty' 2>/dev/null)

# Skip if message is not a string (structured messages like shutdown_request)
[ -z "$MESSAGE" ] && exit 0
echo "$INPUT" | jq -e '.tool_input.message | type == "string"' > /dev/null 2>&1 || exit 0

# --- ADVICE AUTO-LOG ---
# Match: "OBJECTION OBJ-1-01:" or "SMELL SML-1-01:" etc.
if echo "$MESSAGE" | head -1 | grep -qE "^(OBJECTION|SMELL|STEER|FYI) [A-Z]{3}-[0-9]+-[0-9]+:"; then
  TYPE=$(echo "$MESSAGE" | head -1 | grep -oE "^(OBJECTION|SMELL|STEER|FYI)")
  ID=$(echo "$MESSAGE" | head -1 | grep -oE "[A-Z]{3}-[0-9]+-[0-9]+")

  # Only append if this ID isn't already in the file
  if [ -f "$ADVICE" ] && grep -q "$ID" "$ADVICE" 2>/dev/null; then
    : # Already logged, skip duplicate
  else
    # Insert before "## Resolved" so it lands in the ## Open section.
    # Enforcement hooks use sed '/^## Open$/,/^## Resolved$/p' to extract open items.
    if [ -f "$ADVICE" ] && grep -q "^## Resolved" "$ADVICE" 2>/dev/null; then
      # Write entry to temp file, then insert before ## Resolved
      ENTRY_FILE=$(mktemp)
      {
        echo ""
        echo "### ${TYPE} ${ID} — to @${TO}"
        echo "$MESSAGE"
        echo "- Status: open"
        echo ""
      } > "$ENTRY_FILE"
      TMPFILE=$(mktemp)
      # Split at ## Resolved: everything before it + entry + ## Resolved + everything after
      sed '/^## Resolved$/r '"$ENTRY_FILE" "$ADVICE" | sed '/^## Resolved$/{x;d;}' > "$TMPFILE" 2>/dev/null
      # Simpler approach: use awk to insert file contents before the marker
      awk '/^## Resolved$/{while((getline line < "'"$ENTRY_FILE"'") > 0) print line} 1' "$ADVICE" > "$TMPFILE"
      mv "$TMPFILE" "$ADVICE"
      rm -f "$ENTRY_FILE"
    else
      {
        echo ""
        echo "### ${TYPE} ${ID} — to @${TO}"
        echo "$MESSAGE"
        echo "- Status: open"
      } >> "$ADVICE"
    fi
  fi
fi

# --- RESOLUTION AUTO-LOG ---
# Match: "RESOLVE SML-2-01 INCORPORATED: detail here"
if echo "$MESSAGE" | head -1 | grep -qE "^RESOLVE [A-Z]{3}-[0-9]+-[0-9]+ (FIXED|REJECTED|INCORPORATED|NOTED)"; then
  ID=$(echo "$MESSAGE" | head -1 | grep -oE "[A-Z]{3}-[0-9]+-[0-9]+")
  OUTCOME=$(echo "$MESSAGE" | head -1 | grep -oE "(FIXED|REJECTED|INCORPORATED|NOTED)")
  # Everything after "OUTCOME: " is the detail (NOTED may have no colon/detail)
  DETAIL=$(echo "$MESSAGE" | head -1 | sed -E 's/^RESOLVE [^ ]+ [A-Z]+(: ?)?//')
  [ -z "$DETAIL" ] && DETAIL="(no detail)"

  # 1. Remove the original entry from ## Open section so enforcement hooks unblock.
  #    Deletes from the ### heading containing the ID through to the next ### or ## heading.
  if [ -f "$ADVICE" ]; then
    TMPFILE=$(mktemp)
    awk -v id="$ID" '
      /^### / && index($0, id) > 0 { skip=1; next }
      /^(### |## )/ && skip { skip=0 }
      !skip
    ' "$ADVICE" > "$TMPFILE" && mv "$TMPFILE" "$ADVICE"
  fi

  # 2. Append resolution to end of file (after ## Resolved header)
  {
    echo ""
    echo "### ${ID} — ${OUTCOME}"
    echo "- Detail: ${DETAIL}"
  } >> "$ADVICE"
fi

# --- CHECKPOINT AUTO-LOG ---
# Match: summary starts with "checkpoint:" (case-insensitive)
if echo "$SUMMARY" | grep -qiE "^checkpoint:"; then
  {
    echo ""
    echo "### Checkpoint"
    echo "$MESSAGE"
  } >> "$LOG"

  # Clear dirty flag (see mark-dirty.sh)
  rm -f "$POPCORN_DIR/.dirty"
fi

exit 0
