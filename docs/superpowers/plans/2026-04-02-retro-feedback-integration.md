# Retro Feedback Integration Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Integrate three findings from the 2026-04-02 retro into the popcorn-xp plugin: batch checkpoint allowance, retro instructions in protocol, and soft checkpoint frequency enforcement.

**Architecture:** Three independent changes — a protocol text update (R1+R2) and a new PreToolUse hook with counter (R3). R1 and R2 touch protocol.md and the protocol skill. R3 adds a new script and modifies mark-dirty.sh + hooks.json.

**Tech Stack:** Bash (hook scripts), Markdown (protocol docs)

---

### Task 1: Add R1, R2, R3 to improvement backlog

**Files:**
- Modify: `docs/improvement-backlog.md`

- [ ] **Step 1: Append three new backlog items**

Add after the Summary Table's last row (before `| H8 |`), three new entries in the table and three new sections in the body. The sections go after AT3 and before the Summary Table.

Add these sections before the Summary Table:

```markdown
### R1 — Batch checkpoint allowance for repetitive edits
**Priority:** 🟡 Medium

**Context:** The 2026-04-02 "improvement backlog" retro observed the craftsman batching many edits without checkpoints during Task 3 SKILL.md edits. The protocol says "Do NOT batch multiple file edits into one checkpoint." But for mechanical, repetitive changes — applying the same fix pattern across 4 files, renaming a variable in 6 locations — per-edit checkpoints add noise without value. The navigator doesn't gain new information from "applied the same H3 fix to file 4 of 4."

**Recommended solution:** Add a batch checkpoint exception to driver prompt step 5 in `references/protocol.md` and `skills/popcorn-xp-protocol/SKILL.md`:

> **Batch exception:** For mechanical, repetitive edits — the same pattern applied to multiple files (e.g., fixing the same grep pattern in 4 hook scripts) — you may batch them into one checkpoint. State what you did, how many files, and which ones. This exception does NOT apply when each edit requires judgment or when the files differ structurally.

---

### R2 — Retro instructions in protocol prompts
**Priority:** 🟠 High

**Context:** The 2026-04-02 retro noted "Retro feedback requests went unanswered — both agents kept responding about task status instead of process observations." The retro instructions live in SKILL.md (which agents don't read) and one weak line in `protocol.md` Integration Notes: "the lead *may* ask teammates for retro feedback." S10 auto-loads the protocol via skills, so agents DO read it — but the instruction is buried and optional-sounding.

**Recommended solution:** Add a "Retro" section to the protocol skill (`skills/popcorn-xp-protocol/SKILL.md`) between Rotation and Integration Notes. Make it a named section agents will recognize when the lead asks:

> ## Retro
>
> Before shutdown, the lead asks for retro feedback. When you receive a retro request, respond with **process observations**, not task status:
> - What worked well about the pairing dynamic?
> - What made collaboration harder?
> - Did the advice system help or get in the way?
> - Were checkpoints frequent enough for useful navigation?
> - What would you change about the rotation or task breakdown?
>
> Keep it brief (3-5 sentences). Focus on the process, not the code. "The OBJECTION on depth checking caught a real bug" is useful. "I completed task 3" is not — the lead already knows that from the TaskList.

Also update the Integration Notes line from "the lead *may* ask" to reference the new section.

---

### R3 — Soft checkpoint frequency enforcement via PreToolUse counter
**Priority:** 🟡 Medium

**Context:** The 2026-04-02 retro identified that `remind-checkpoint.sh` only fires on `TeammateIdle`. A driver who keeps editing without going idle (the exact Task 3 failure) never receives a checkpoint reminder. The retro recommends "mechanical enforcement for checkpoint frequency — perhaps a hook that counts edits since last `session log` call."

The canonical hooks docs confirm PreToolUse on Edit/Write can inject `additionalContext` (exit 0 with JSON) without blocking the edit. The existing `mark-dirty.sh` already fires on PreToolUse Edit/Write and uses a flag file. It can be extended to maintain a counter.

**Recommended solution:** Modify `mark-dirty.sh` to:
1. Read stdin to extract `tool_input.file_path`
2. Skip files under `.popcorn-xp/` (session bookkeeping shouldn't count)
3. Increment a counter file (`.popcorn-xp/{team}/.edit-count`) instead of just touching `.dirty`
4. When the counter reaches 3+, output `{"additionalContext": "Popcorn XP: You have N file edits since your last checkpoint. Send a checkpoint to your navigator and log it: .popcorn-xp/{team}/session log 'what you did'"}` to stdout
5. Still exit 0 (soft — doesn't block the edit)

The `session log` command already does `rm -f "$DIR/.dirty"`. Extend it to also `rm -f "$DIR/.edit-count"` to reset the counter.

Update `remind-checkpoint.sh` to also read the counter for its message (so TeammateIdle reminders show the count too).

**Files affected:** `hooks/scripts/mark-dirty.sh`, `hooks/scripts/remind-checkpoint.sh`, `skills/popcorn-xp/SKILL.md` (session script template — add counter reset to `log` subcommand)
```

Add these rows to the Summary Table (before `| H8 |`):

```markdown
| R1 | Batch checkpoint allowance | 🟡 Pending | protocol.md, protocol skill |
| R2 | Retro instructions in protocol | 🟠 Pending | protocol skill |
| R3 | Soft checkpoint frequency enforcement | 🟡 Pending | mark-dirty.sh, remind-checkpoint.sh, session script |
```

- [ ] **Step 2: Commit**

```bash
git add docs/improvement-backlog.md
git commit -m "docs: add R1, R2, R3 retro findings to improvement backlog"
```

---

### Task 2: Implement R1 — Batch checkpoint allowance

**Files:**
- Modify: `references/protocol.md:69-76` (driver prompt step 5)
- Modify: `skills/popcorn-xp-protocol/SKILL.md` (no step 5 — but the Session Files section has checkpoint logging instructions)

- [ ] **Step 1: Update driver prompt step 5 in references/protocol.md**

In `references/protocol.md`, find the driver prompt step 5 block (around line 69-76):

```text
5. Work in small steps. After EACH file edit, test run, or discovery:
   **5a.** Send a checkpoint to your navigator:
      ...
   **5b.** Log it:
      ...
   Do NOT batch multiple file edits into one checkpoint. One edit = one checkpoint = one log entry.
   The navigator can only advise on what they know about. More checkpoints = better advice.
```

Replace the last two lines with:

```text
   One edit = one checkpoint = one log entry. The navigator can only advise on what
   they know about. More checkpoints = better advice.
   **Batch exception:** For mechanical, repetitive edits — the same pattern applied
   to multiple files (e.g., fixing the same grep in 4 scripts, renaming a variable
   across 6 files) — you may batch into one checkpoint. State what you did, how many
   files, and list them. This does NOT apply when each edit requires judgment or when
   the files differ structurally.
```

- [ ] **Step 2: Update protocol skill with matching language**

In `skills/popcorn-xp-protocol/SKILL.md`, after the "After each checkpoint, log it:" code block (around line 115-118), add the batch exception note:

After line 118 (`````), add:

```text

One edit = one checkpoint = one log entry. **Batch exception:** For mechanical,
repetitive edits (same pattern across multiple files), batch into one checkpoint.
State what you did, how many files, and list them.
```

- [ ] **Step 3: Commit**

```bash
git add references/protocol.md skills/popcorn-xp-protocol/SKILL.md
git commit -m "feat(protocol): add batch checkpoint exception for repetitive edits (R1)"
```

---

### Task 3: Implement R2 — Retro instructions in protocol

**Files:**
- Modify: `skills/popcorn-xp-protocol/SKILL.md` (add Retro section)
- Modify: `references/protocol.md` (update Integration Notes line)

- [ ] **Step 1: Add Retro section to protocol skill**

In `skills/popcorn-xp-protocol/SKILL.md`, insert a new section between `## Rotation` (ends around line 201) and `## Integration Notes` (starts at line 203):

```markdown
## Retro

Before shutdown, the lead asks for retro feedback. When you receive a retro request, respond with **process observations**, not task status:
- What worked well about the pairing dynamic?
- What made collaboration harder?
- Did the advice system help or get in the way?
- Were checkpoints frequent enough for useful navigation?
- What would you change about the rotation or task breakdown?

Keep it brief (3-5 sentences). Focus on the process, not the code. "The OBJECTION on depth checking caught a real bug" is useful. "I completed task 3" is not — the lead already knows that from the TaskList.
```

- [ ] **Step 2: Update Integration Notes in protocol skill**

In `skills/popcorn-xp-protocol/SKILL.md`, replace the Integration Notes shutdown bullet (line 209):

```text
- Before shutdown, the lead may ask teammates for retro feedback: "What worked well? What would you change about the process?" Respond briefly.
```

With:

```text
- Before shutdown, the lead asks for retro feedback. See the Retro section above — respond with process observations, not task summaries.
```

- [ ] **Step 3: Update Integration Notes in references/protocol.md**

In `references/protocol.md`, find the matching line in the Integration Notes section (line 555):

```text
- Before shutdown, the lead may ask teammates for retro feedback: "What worked well? What would you change about the process?" Respond briefly — your observations about the pairing dynamic, the advice system, and the task breakdown help improve future sessions.
```

Replace with:

```text
- Before shutdown, the lead asks for retro feedback. Respond with **process observations** — what worked about the pairing dynamic, what made collaboration harder, whether checkpoints and advice helped. Focus on the process, not the code. See the protocol skill's Retro section for the full prompt. Keep it to 3-5 sentences.
```

- [ ] **Step 4: Add Retro section to references/protocol.md driver and navigator prompts**

In `references/protocol.md`, add to the driver prompt's Important section (after line 166 "approve it immediately" bullet):

```text
- When the lead asks for retro feedback, respond with process observations (pairing
  dynamic, advice quality, checkpoint frequency, rotation). Not task status — the lead
  already has that from the TaskList. See the Retro section in the protocol skill.
```

Add the same bullet to the navigator prompt's Important section (after line 312 "approve it immediately" bullet):

```text
- When the lead asks for retro feedback, respond with process observations (pairing
  dynamic, advice quality, checkpoint frequency, rotation). Not task status — the lead
  already has that from the TaskList. See the Retro section in the protocol skill.
```

- [ ] **Step 5: Commit**

```bash
git add skills/popcorn-xp-protocol/SKILL.md references/protocol.md
git commit -m "feat(protocol): add retro instructions to protocol prompts (R2)"
```

---

### Task 4: Implement R3 — Soft checkpoint frequency enforcement

**Files:**
- Modify: `hooks/scripts/mark-dirty.sh`
- Modify: `hooks/scripts/remind-checkpoint.sh`
- Modify: `skills/popcorn-xp/SKILL.md` (session script template — counter reset in `log` subcommand)

- [ ] **Step 1: Rewrite mark-dirty.sh to count edits and inject context**

Replace the entire content of `hooks/scripts/mark-dirty.sh` with:

```bash
#!/bin/bash
set -euo pipefail

# mark-dirty.sh
# PreToolUse hook on Edit/Write: counts uncheckpointed edits.
# Increments .edit-count each time. After 3+ edits, injects
# additionalContext reminding the driver to checkpoint.
# The counter resets when the teammate runs `session log`.
# Skips .popcorn-xp/ paths (session bookkeeping).
# No-op when no active popcorn-xp session.

POPCORN_DIR="${CLAUDE_PROJECT_DIR:-.}/.popcorn-xp"
TEAM=$(cat "$POPCORN_DIR/.active-team" 2>/dev/null || true)
[ -z "$TEAM" ] && exit 0
[ ! -d "$POPCORN_DIR/$TEAM" ] && exit 0

# Read file_path from stdin (PreToolUse input)
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)

# Skip session bookkeeping files
case "$FILE_PATH" in
  */.popcorn-xp/*) exit 0 ;;
esac

COUNT_FILE="$POPCORN_DIR/$TEAM/.edit-count"
DIRTY_FILE="$POPCORN_DIR/$TEAM/.dirty"

# Increment counter
COUNT=0
[ -f "$COUNT_FILE" ] && COUNT=$(cat "$COUNT_FILE" 2>/dev/null || echo 0)
COUNT=$((COUNT + 1))
echo "$COUNT" > "$COUNT_FILE"

# Always set dirty flag for remind-checkpoint.sh
touch "$DIRTY_FILE"

# After 3+ uncheckpointed edits, inject a soft reminder
if [ "$COUNT" -ge 3 ]; then
  cat <<EOJSON
{"additionalContext":"Popcorn XP: You have $COUNT file edits since your last checkpoint. Send a checkpoint to your navigator and log it: .popcorn-xp/$TEAM/session log 'what you did'"}
EOJSON
fi

exit 0
```

- [ ] **Step 2: Update remind-checkpoint.sh to show edit count**

Replace the content of `hooks/scripts/remind-checkpoint.sh` with:

```bash
#!/bin/bash
set -euo pipefail

# remind-checkpoint.sh
# TeammateIdle hook: reminds driver to checkpoint after uncheckpointed edits.
# Checks for .dirty flag set by mark-dirty.sh (PreToolUse on Edit/Write).
# The flag is cleared when the teammate runs the session log command.
# Blocking — exits 2 with plain text feedback to prevent idle transition.
# No-op when no active popcorn-xp session or no dirty flag.

POPCORN_DIR="${CLAUDE_PROJECT_DIR:-.}/.popcorn-xp"
TEAM=$(cat "$POPCORN_DIR/.active-team" 2>/dev/null || true)
[ -z "$TEAM" ] && exit 0

[ ! -f "$POPCORN_DIR/$TEAM/.dirty" ] && exit 0

# Read edit count if available
COUNT_FILE="$POPCORN_DIR/$TEAM/.edit-count"
COUNT=0
[ -f "$COUNT_FILE" ] && COUNT=$(cat "$COUNT_FILE" 2>/dev/null || echo 0)

if [ "$COUNT" -gt 0 ]; then
  echo "Popcorn XP: You have $COUNT file edit(s) since your last checkpoint. Send a checkpoint to your navigator and log it: .popcorn-xp/$TEAM/session log 'what you did'" >&2
else
  echo "Popcorn XP: You edited files since your last checkpoint. Send a checkpoint to your navigator and log it: .popcorn-xp/$TEAM/session log 'what you did'" >&2
fi

# Remove flags so we don't nag on every idle cycle
rm -f "$POPCORN_DIR/$TEAM/.dirty"
rm -f "$POPCORN_DIR/$TEAM/.edit-count"

exit 2
```

- [ ] **Step 3: Update session script template to reset counter on `log`**

In `skills/popcorn-xp/SKILL.md`, find the session script `log` subcommand (line 169):

```bash
  log) printf '\n### Checkpoint\n%s\n' "$*" >> "$DIR/LOG.md"; rm -f "$DIR/.dirty" ;;
```

Replace with:

```bash
  log) printf '\n### Checkpoint\n%s\n' "$*" >> "$DIR/LOG.md"; rm -f "$DIR/.dirty" "$DIR/.edit-count" ;;
```

- [ ] **Step 4: Commit**

```bash
git add hooks/scripts/mark-dirty.sh hooks/scripts/remind-checkpoint.sh skills/popcorn-xp/SKILL.md
git commit -m "feat(hooks): soft checkpoint frequency enforcement via edit counter (R3)"
```

---

### Task 5: Write tests for R3

**Files:**
- Modify: `tests/test-hooks.sh`

- [ ] **Step 1: Add R3 test section to test-hooks.sh**

Insert a new test section before the Results section (before `# ============================================================` / `# Results`). Add after section 10 (Output channel consistency):

```bash
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
```

- [ ] **Step 2: Run the tests**

```bash
bash tests/test-hooks.sh
```

Expected: All tests pass, including the new R3 section.

- [ ] **Step 3: Commit**

```bash
git add tests/test-hooks.sh
git commit -m "test(hooks): add R3 edit counter and checkpoint enforcement tests"
```

---

### Task 6: Update backlog status to Done

**Files:**
- Modify: `docs/improvement-backlog.md`

- [ ] **Step 1: Mark R1, R2, R3 as Done in summary table**

Replace:
```markdown
| R1 | Batch checkpoint allowance | 🟡 Pending | protocol.md, protocol skill |
| R2 | Retro instructions in protocol | 🟠 Pending | protocol skill |
| R3 | Soft checkpoint frequency enforcement | 🟡 Pending | mark-dirty.sh, remind-checkpoint.sh, session script |
```

With:
```markdown
| ✅ R1 | Batch checkpoint allowance | Done | protocol.md, protocol skill |
| ✅ R2 | Retro instructions in protocol | Done | protocol skill, driver/navigator prompts |
| ✅ R3 | Soft checkpoint frequency enforcement | Done | mark-dirty.sh, remind-checkpoint.sh, session script |
```

- [ ] **Step 2: Commit**

```bash
git add docs/improvement-backlog.md
git commit -m "docs: mark R1, R2, R3 as done in improvement backlog"
```
