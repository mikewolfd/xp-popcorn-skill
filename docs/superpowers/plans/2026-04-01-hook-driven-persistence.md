# Hook-Driven Persistence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate dual-write burden by auto-populating ADVICE.md and LOG.md from SendMessage via hooks, fix two dead/incorrect hooks, and update protocol templates to match.

**Architecture:** PostToolUse hook on SendMessage parses advice/checkpoint markers from message content and auto-appends to the corresponding session file. PreToolUse hook on Edit/Write tracks uncheckpointed edits. Protocol templates drop all "append to ADVICE.md/LOG.md" instructions — agents just use SendMessage, the system handles persistence.

**Tech Stack:** Bash hooks with jq for JSON parsing, Claude Code hook system (PreToolUse/PostToolUse/TeammateIdle/TaskCompleted), Markdown session files.

---

## File Structure

### New files
- `hooks/scripts/auto-log-messages.sh` — PostToolUse on SendMessage: auto-populates ADVICE.md and LOG.md from message content
- `hooks/scripts/mark-dirty.sh` — PreToolUse on Edit/Write: sets dirty flag when driver edits files
- `hooks/scripts/remind-checkpoint.sh` — TeammateIdle: reminds driver to checkpoint after uncheckpointed edits
- `hooks/scripts/init-session.sh` — PreToolUse on TaskUpdate: auto-creates .popcorn-xp/ directory on first task start

### Modified files
- `hooks/scripts/check-rotation.sh` — Fix hardcoded tasks directory path (P0 bug)
- `hooks/scripts/remind-unread-advice.sh` — Fix incorrect SMELL blocking claim (P0 bug)
- `hooks/hooks.json` — Register all new hooks
- `references/protocol.md` — Remove dual-write instructions, add rotation sections, simplify advice format
- `SKILL.md` — Add verification task guidance, update shutdown pattern, add code-reviewer independence note
- `agents/expert.md` — Add rotation awareness
- `agents/craftsman.md` — Add rotation awareness

---

## Task 1: Fix P0 bugs in existing hooks

Two hooks have bugs discovered during the demo session that must be fixed before anything else.

**Files:**
- Modify: `hooks/scripts/check-rotation.sh:10`
- Modify: `hooks/scripts/remind-unread-advice.sh:33`

### check-rotation.sh: Hardcoded tasks directory (dead code)

The hook hardcodes `TASKS_DIR="${HOME}/.claude/tasks/popcorn-xp"` but TeamCreate generates random names like `curried-tickling-lynx`. The tasks directory is actually at `~/.claude/tasks/curried-tickling-lynx/`. The hook silently exits at line 12 (`[ ! -d "$TASKS_DIR" ] && exit 0`) every time — it never fires.

The TaskCompleted hook receives JSON on stdin that may include `team_name`. But the current hook ignores stdin entirely.

- [ ] **Step 1: Fix check-rotation.sh to read team_name from stdin**

Replace lines 9-12 of `hooks/scripts/check-rotation.sh`:

```bash
TASKS_DIR="${HOME}/.claude/tasks/popcorn-xp"

[ ! -d "$TASKS_DIR" ] && exit 0
```

with:

```bash
# Read hook input from stdin — TaskCompleted provides team_name
INPUT=$(cat)
TEAM_NAME=$(echo "$INPUT" | jq -r '.team_name // empty' 2>/dev/null)

# If no team_name in hook input, scan for the most recently modified tasks directory
if [ -z "$TEAM_NAME" ]; then
  TASKS_BASE="${HOME}/.claude/tasks"
  [ ! -d "$TASKS_BASE" ] && exit 0
  TASKS_DIR=$(ls -td "$TASKS_BASE"/*/ 2>/dev/null | head -1)
  [ -z "$TASKS_DIR" ] && exit 0
  # Remove trailing slash
  TASKS_DIR="${TASKS_DIR%/}"
else
  TASKS_DIR="${HOME}/.claude/tasks/${TEAM_NAME}"
fi

[ ! -d "$TASKS_DIR" ] && exit 0
```

- [ ] **Step 2: Verify check-rotation.sh with sample input**

Run:
```bash
echo '{"team_name":"test-team"}' | bash hooks/scripts/check-rotation.sh
echo $?
```
Expected: exit 0 (no tasks directory exists for test-team, so it no-ops cleanly)

Run:
```bash
echo '{}' | bash hooks/scripts/check-rotation.sh
echo $?
```
Expected: exit 0 (no team_name, falls back to scan, likely no-ops)

### remind-unread-advice.sh: Incorrect SMELL blocking claim

- [ ] **Step 3: Fix remind-unread-advice.sh wording**

Replace line 33 of `hooks/scripts/remind-unread-advice.sh`:

```bash
echo "{\"systemMessage\":\"Popcorn XP: ${total} open advice item(s) in .popcorn-xp/ADVICE.md (${summary}). Read the file and resolve items before your next action — OBJECTIONs and SMELLs must be resolved before task completion.\"}"
```

with:

```bash
echo "{\"systemMessage\":\"Popcorn XP: ${total} open advice item(s) in .popcorn-xp/ADVICE.md (${summary}). OBJECTIONs must be resolved before task completion. SMELLs, STEERs, and FYIs are your call — resolve if you can, but don't let them hold up good work.\"}"
```

- [ ] **Step 4: Verify remind-unread-advice.sh with a test ADVICE.md**

Run:
```bash
mkdir -p /tmp/test-popcorn && cat > /tmp/test-popcorn/ADVICE.md << 'EOF'
# Popcorn XP Advice

## Open

### SMELL SML-1-01 — from @expert to @craftsman
- Status: open

## Resolved
EOF
CLAUDE_PROJECT_DIR=/tmp/test-popcorn bash hooks/scripts/remind-unread-advice.sh
```
Expected: systemMessage mentioning "1 SMELL(s)" and "SMELLs, STEERs, and FYIs are your call"

- [ ] **Step 5: Commit P0 bug fixes**

```bash
git add hooks/scripts/check-rotation.sh hooks/scripts/remind-unread-advice.sh
git commit -m "fix: repair rotation hook (hardcoded path) and advice reminder wording

check-rotation.sh was dead code — it hardcoded 'popcorn-xp' as the tasks
directory name, but TeamCreate generates random team names. Now reads
team_name from hook stdin, falls back to most-recent-directory scan.

remind-unread-advice.sh incorrectly claimed SMELLs block task completion.
Only OBJECTIONs block. Fixed wording to match protocol."
```

---

## Task 2: Create auto-log-messages.sh hook

The core change: PostToolUse on SendMessage that auto-populates ADVICE.md and LOG.md from message content. This eliminates the dual-write burden.

**Files:**
- Create: `hooks/scripts/auto-log-messages.sh`
- Modify: `hooks/hooks.json`

- [ ] **Step 1: Verify jq is available**

Run: `which jq && jq --version`
Expected: jq path and version (1.6+). If missing, note it as a dependency.

- [ ] **Step 2: Create auto-log-messages.sh**

Write `hooks/scripts/auto-log-messages.sh`:

```bash
#!/bin/bash
set -euo pipefail

# auto-log-messages.sh
# PostToolUse hook on SendMessage: auto-populates ADVICE.md and LOG.md
# from message content. Agents send one message — the system handles persistence.
#
# Detects three patterns:
#   1. Advice: message starts with OBJECTION/SMELL/STEER/FYI + ID
#      → appends to ADVICE.md under ## Open
#   2. Resolution: message starts with "RESOLVE {ID} {OUTCOME}:"
#      → appends to ADVICE.md under ## Resolved
#   3. Checkpoint: summary starts with "checkpoint:" (case-insensitive)
#      → appends to LOG.md
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

  # Only append if this ID isn't already in ## Open
  if [ -f "$ADVICE" ] && grep -q "$ID" "$ADVICE" 2>/dev/null; then
    : # Already logged, skip duplicate
  else
    {
      echo ""
      echo "### ${TYPE} ${ID} — to @${TO}"
      echo "$MESSAGE"
      echo "- Status: open"
    } >> "$ADVICE"
  fi
fi

# --- RESOLUTION AUTO-LOG ---
# Match: "RESOLVE SML-2-01 INCORPORATED: detail here"
if echo "$MESSAGE" | head -1 | grep -qE "^RESOLVE [A-Z]{3}-[0-9]+-[0-9]+ (FIXED|REJECTED|INCORPORATED|NOTED)"; then
  ID=$(echo "$MESSAGE" | head -1 | grep -oE "[A-Z]{3}-[0-9]+-[0-9]+")
  OUTCOME=$(echo "$MESSAGE" | head -1 | grep -oE "(FIXED|REJECTED|INCORPORATED|NOTED)")
  # Everything after "OUTCOME: " is the detail
  DETAIL=$(echo "$MESSAGE" | head -1 | sed -E 's/^RESOLVE [^ ]+ [A-Z]+: ?//')

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
```

- [ ] **Step 3: Make it executable**

Run: `chmod +x hooks/scripts/auto-log-messages.sh`

- [ ] **Step 4: Test advice auto-logging**

Run:
```bash
mkdir -p /tmp/test-popcorn && printf "# Popcorn XP Advice\n\n## Open\n\n## Resolved\n" > /tmp/test-popcorn/ADVICE.md
echo '{"tool_input":{"to":"craftsman","message":"SMELL SML-2-01: topoSort uses O(n) indexOf\nFile: demo/task-runner.js:64\nObservation: path.indexOf called on every visit","summary":"SMELL SML-2-01: topoSort indexOf"}}' | CLAUDE_PROJECT_DIR=/tmp/test-popcorn bash hooks/scripts/auto-log-messages.sh
cat /tmp/test-popcorn/ADVICE.md
```
Expected: ADVICE.md now has a `### SMELL SML-2-01 — to @craftsman` entry under ## Open

- [ ] **Step 5: Test duplicate prevention**

Run the same command again:
```bash
echo '{"tool_input":{"to":"craftsman","message":"SMELL SML-2-01: topoSort uses O(n) indexOf\nFile: demo/task-runner.js:64\nObservation: path.indexOf called on every visit","summary":"SMELL SML-2-01: topoSort indexOf"}}' | CLAUDE_PROJECT_DIR=/tmp/test-popcorn bash hooks/scripts/auto-log-messages.sh
grep -c "SML-2-01" /tmp/test-popcorn/ADVICE.md
```
Expected: count is 1 (not duplicated)

- [ ] **Step 6: Test resolution auto-logging**

Run:
```bash
echo '{"tool_input":{"to":"expert","message":"RESOLVE SML-2-01 INCORPORATED: Added visiting Set for O(1) detection","summary":"resolve SML-2-01"}}' | CLAUDE_PROJECT_DIR=/tmp/test-popcorn bash hooks/scripts/auto-log-messages.sh
cat /tmp/test-popcorn/ADVICE.md
```
Expected: ADVICE.md now has `### SML-2-01 — INCORPORATED` entry

- [ ] **Step 7: Test checkpoint auto-logging**

Run:
```bash
echo "# Popcorn XP Log" > /tmp/test-popcorn/LOG.md
echo '{"tool_input":{"to":"expert","message":"Edited demo/task-runner.js:47 — added depth guard to parseBlock(). Tests pass.","summary":"checkpoint: edited task-runner.js"}}' | CLAUDE_PROJECT_DIR=/tmp/test-popcorn bash hooks/scripts/auto-log-messages.sh
cat /tmp/test-popcorn/LOG.md
```
Expected: LOG.md now has a `### Checkpoint` entry with the message content

- [ ] **Step 8: Test no-op on regular messages**

Run:
```bash
echo '{"tool_input":{"to":"team-lead","message":"Task 1 complete. Ready for next.","summary":"task 1 done"}}' | CLAUDE_PROJECT_DIR=/tmp/test-popcorn bash hooks/scripts/auto-log-messages.sh
echo $?
```
Expected: exit 0, no changes to ADVICE.md or LOG.md

- [ ] **Step 9: Test no-op on structured messages (shutdown_request)**

Run:
```bash
echo '{"tool_input":{"to":"craftsman","message":{"type":"shutdown_request"}}}' | CLAUDE_PROJECT_DIR=/tmp/test-popcorn bash hooks/scripts/auto-log-messages.sh
echo $?
```
Expected: exit 0, no changes

- [ ] **Step 10: Register PostToolUse hook in hooks.json**

Add to `hooks/hooks.json`, as a new top-level key in the `hooks` object after the existing `PreToolUse` block:

```json
"PostToolUse": [
  {
    "matcher": "SendMessage",
    "hooks": [
      {
        "type": "command",
        "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/auto-log-messages.sh",
        "timeout": 10
      }
    ]
  }
]
```

- [ ] **Step 11: Clean up test files and commit**

Run:
```bash
rm -rf /tmp/test-popcorn
git add hooks/scripts/auto-log-messages.sh hooks/hooks.json
git commit -m "feat: auto-log advice and checkpoints from SendMessage via hook

PostToolUse hook on SendMessage detects advice format markers
(OBJECTION/SMELL/STEER/FYI + ID) and checkpoint markers
(summary starts with 'checkpoint:') and auto-appends to
ADVICE.md and LOG.md respectively.

Also detects RESOLVE messages and auto-appends to ## Resolved.
Includes duplicate prevention for advice entries.

Agents no longer need to manually write to session files —
just SendMessage, the system handles persistence."
```

---

## Task 3: Create checkpoint enforcement hooks

Three small hooks that work together: mark-dirty tracks edits, remind-checkpoint nudges idle drivers, init-session ensures .popcorn-xp/ exists.

**Files:**
- Create: `hooks/scripts/mark-dirty.sh`
- Create: `hooks/scripts/remind-checkpoint.sh`
- Create: `hooks/scripts/init-session.sh`
- Modify: `hooks/hooks.json`

- [ ] **Step 1: Create mark-dirty.sh**

Write `hooks/scripts/mark-dirty.sh`:

```bash
#!/bin/bash
set -euo pipefail

# mark-dirty.sh
# PreToolUse hook on Edit/Write: sets a dirty flag when files are edited.
# The remind-checkpoint.sh TeammateIdle hook checks this flag and nudges
# the driver to send a checkpoint if they haven't since the last edit.
# No-op when no active popcorn-xp session.

POPCORN_DIR="${CLAUDE_PROJECT_DIR:-.}/.popcorn-xp"
[ ! -d "$POPCORN_DIR" ] && exit 0

touch "$POPCORN_DIR/.dirty"
exit 0
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x hooks/scripts/mark-dirty.sh`

- [ ] **Step 3: Create remind-checkpoint.sh**

Write `hooks/scripts/remind-checkpoint.sh`:

```bash
#!/bin/bash
set -euo pipefail

# remind-checkpoint.sh
# TeammateIdle hook: reminds driver to checkpoint after uncheckpointed edits.
# Checks for .dirty flag set by mark-dirty.sh (PreToolUse on Edit/Write).
# The flag is cleared by auto-log-messages.sh when a checkpoint is logged.
# Non-blocking — just a nudge via systemMessage.
# No-op when no active popcorn-xp session or no dirty flag.

POPCORN_DIR="${CLAUDE_PROJECT_DIR:-.}/.popcorn-xp"
[ ! -f "$POPCORN_DIR/.dirty" ] && exit 0

echo '{"systemMessage":"Popcorn XP: You edited files since your last checkpoint. Send a checkpoint to your navigator — they can only advise on what they can see. Use summary: \"checkpoint: ...\" so it gets logged automatically."}'

# Remove flag so we don't nag on every idle cycle
rm -f "$POPCORN_DIR/.dirty"

exit 0
```

- [ ] **Step 4: Make it executable**

Run: `chmod +x hooks/scripts/remind-checkpoint.sh`

- [ ] **Step 5: Create init-session.sh**

Write `hooks/scripts/init-session.sh`:

```bash
#!/bin/bash
set -euo pipefail

# init-session.sh
# PreToolUse hook on TaskUpdate: auto-creates .popcorn-xp/ directory and
# session files when a task is first marked in_progress.
# Replaces the manual "create .popcorn-xp/ if it doesn't exist" instruction
# in the driver prompt template.
# No-op if .popcorn-xp/ already exists.

POPCORN_DIR="${CLAUDE_PROJECT_DIR:-.}/.popcorn-xp"

# Only initialize if the directory doesn't exist yet
[ -d "$POPCORN_DIR" ] && exit 0

# Check if this is a status change to in_progress
INPUT=$(cat)
STATUS=$(echo "$INPUT" | jq -r '.tool_input.status // empty' 2>/dev/null)
[ "$STATUS" != "in_progress" ] && exit 0

mkdir -p "$POPCORN_DIR"
echo "# Popcorn XP Log" > "$POPCORN_DIR/LOG.md"
printf "# Popcorn XP Advice\n\n## Open\n\n## Resolved\n" > "$POPCORN_DIR/ADVICE.md"

exit 0
```

- [ ] **Step 6: Make it executable**

Run: `chmod +x hooks/scripts/init-session.sh`

- [ ] **Step 7: Test mark-dirty and remind-checkpoint together**

Run:
```bash
mkdir -p /tmp/test-popcorn
# Simulate an edit (mark dirty)
CLAUDE_PROJECT_DIR=/tmp/test-popcorn bash hooks/scripts/mark-dirty.sh
ls -la /tmp/test-popcorn/.dirty
# Simulate going idle (should remind)
CLAUDE_PROJECT_DIR=/tmp/test-popcorn bash hooks/scripts/remind-checkpoint.sh
# Simulate going idle again (should NOT remind — flag was cleared)
CLAUDE_PROJECT_DIR=/tmp/test-popcorn bash hooks/scripts/remind-checkpoint.sh
```
Expected: First idle produces systemMessage. Second idle produces nothing (flag cleared).

- [ ] **Step 8: Test init-session.sh**

Run:
```bash
rm -rf /tmp/test-popcorn2
echo '{"tool_input":{"taskId":"1","status":"in_progress"}}' | CLAUDE_PROJECT_DIR=/tmp/test-popcorn2 bash hooks/scripts/init-session.sh
ls /tmp/test-popcorn2/.popcorn-xp/
cat /tmp/test-popcorn2/.popcorn-xp/ADVICE.md
```
Expected: Directory created with LOG.md and ADVICE.md with correct headers.

- [ ] **Step 9: Test init-session.sh idempotence (no-op if exists)**

Run:
```bash
echo "extra content" >> /tmp/test-popcorn2/.popcorn-xp/LOG.md
echo '{"tool_input":{"taskId":"2","status":"in_progress"}}' | CLAUDE_PROJECT_DIR=/tmp/test-popcorn2 bash hooks/scripts/init-session.sh
cat /tmp/test-popcorn2/.popcorn-xp/LOG.md
```
Expected: LOG.md still has "extra content" — init-session didn't overwrite.

- [ ] **Step 10: Register all three hooks in hooks.json**

Add to the `PreToolUse` array in `hooks/hooks.json`:

```json
{
  "matcher": "Edit",
  "hooks": [
    {
      "type": "command",
      "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/mark-dirty.sh",
      "timeout": 5
    }
  ]
},
{
  "matcher": "Write",
  "hooks": [
    {
      "type": "command",
      "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/mark-dirty.sh",
      "timeout": 5
    }
  ]
},
{
  "matcher": "TaskUpdate",
  "hooks": [
    {
      "type": "command",
      "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/init-session.sh",
      "timeout": 5
    }
  ]
}
```

Add to the `TeammateIdle` hooks array (after existing remind-unread-advice):

```json
{
  "type": "command",
  "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/remind-checkpoint.sh",
  "timeout": 5
}
```

- [ ] **Step 11: Clean up test files and commit**

Run:
```bash
rm -rf /tmp/test-popcorn /tmp/test-popcorn2
git add hooks/scripts/mark-dirty.sh hooks/scripts/remind-checkpoint.sh hooks/scripts/init-session.sh hooks/hooks.json
git commit -m "feat: add checkpoint enforcement and session init hooks

mark-dirty.sh (PreToolUse on Edit/Write): sets .dirty flag when
files are edited without a subsequent checkpoint.

remind-checkpoint.sh (TeammateIdle): nudges driver to checkpoint
when .dirty flag exists. Clears flag after reminding once.

init-session.sh (PreToolUse on TaskUpdate): auto-creates .popcorn-xp/
directory with LOG.md and ADVICE.md on first task start. Replaces
manual session initialization in driver prompt."
```

---

## Task 4: Update protocol.md — remove dual-write, add rotation awareness

The biggest edit. Simplifies driver/navigator templates, adds rotation sections, removes manual ADVICE.md/LOG.md write instructions, updates advice format.

**Files:**
- Modify: `references/protocol.md:67-71` (driver checkpoint instruction)
- Modify: `references/protocol.md:75-77` (driver advice handling)
- Modify: `references/protocol.md:84-91` (driver completion)
- Modify: `references/protocol.md:93-99` (session files section)
- Modify: `references/protocol.md:101-114` (important section)
- Modify: `references/protocol.md:143-146` (navigator advice instruction)
- Modify: `references/protocol.md:160-162` (navigator OBJECTION handling)
- Modify: `references/protocol.md:203-206` (navigator important section)
- Modify: `references/protocol.md:245-251` (advisor LOG.md)
- Modify: `references/protocol.md:306-348` (ADVICE.md format section)

- [ ] **Step 1: Update driver checkpoint instruction (lines 67-72)**

Replace:
```text
5. Work in small steps. After EVERY edit, test, or discovery:
   a. SendMessage to "{navigator_name}" with a checkpoint. Include the `summary` field:
      SendMessage(to: "{navigator_name}", summary: "checkpoint: edited parser.ts",
        message: "CHECKPOINT: [what you just did, what file:line, what you learned, what's next]")
   b. Append the same checkpoint to .popcorn-xp/LOG.md
   The navigator can only advise on what they know about. More checkpoints = better advice.
```

with:
```text
5. Work in small steps. After EACH file edit, test run, or discovery, send a checkpoint:
      SendMessage(to: "{navigator_name}", summary: "checkpoint: edited parser.ts",
        message: "[what you just did, what file:line, what you learned, what's next]")
   LOG.md is updated automatically from your checkpoint messages.
   Do NOT batch multiple file edits into one checkpoint. One edit = one message.
   The navigator can only advise on what they know about. More checkpoints = better advice.
```

- [ ] **Step 2: Update driver advice handling (lines 75-77)**

Replace:
```text
   - OBJECTION: Someone thinks something is wrong. Engage with it — fix the issue
     if they're right, or reply with "REJECT OBJ-X-XX: [your reasoning]" if they're
     not. Both are valid. Append resolution to ADVICE.md. OBJECTIONs block completion.
```

with:
```text
   - OBJECTION: Someone thinks something is wrong. Engage with it — fix the issue
     if they're right, or reply with "REJECT OBJ-X-XX: [your reasoning]" if they're
     not. Both are valid. Send a resolution message (see Resolving Advice below).
     OBJECTIONs block completion.
```

- [ ] **Step 3: Update driver completion (lines 84-91)**

Replace:
```text
7. When your task goal is done:
   a. Read .popcorn-xp/ADVICE.md one final time. Engage with any open OBJECTIONs
      (the TaskCompleted hook blocks on these). Other open items won't block you,
      but resolve them if you can — it helps the next driver.
   b. Mark the task completed with TaskUpdate.
   c. SendMessage to team-lead: "Task [id] complete. [brief summary]. Recommend
      [next driver role] for task [next id]."
   d. Check TaskList for your next task, or go idle.
```

with:
```text
7. When your task goal is done:
   a. Read .popcorn-xp/ADVICE.md one final time. Engage with any open OBJECTIONs
      (the TaskCompleted hook blocks on these). Other open items won't block you,
      but resolve them if you can — it helps the next driver.
   b. Mark the task completed with TaskUpdate.
   c. SendMessage to team-lead: "Task [id] complete. [brief summary]."
      The lead assigns the next driver based on rotation — don't recommend yourself.
   d. Check TaskList for your next task, or go idle.
```

- [ ] **Step 4: Update session files section (lines 93-99)**

Replace:
```text
## Session Files

On your first action, create .popcorn-xp/ if it doesn't exist and initialize:
- LOG.md with a header: "# Popcorn XP Log"
- ADVICE.md with headers: "# Popcorn XP Advice\n\n## Open\n\n## Resolved"

Append to LOG.md after each checkpoint. Never rewrite existing entries.
```

with:
```text
## Session Files

The .popcorn-xp/ directory and session files (LOG.md, ADVICE.md) are created
automatically when you start your first task. You do not need to create them.

LOG.md and ADVICE.md are populated automatically from your SendMessage calls:
- Checkpoint messages (summary starting "checkpoint:") → appended to LOG.md
- Advice messages (OBJECTION/SMELL/STEER/FYI + ID) → appended to ADVICE.md
- Resolution messages ("RESOLVE {ID} {OUTCOME}: ...") → appended to ADVICE.md

You should still READ these files (before starting work, before completing) but
you do not need to WRITE to them directly.
```

- [ ] **Step 5: Add rotation section to driver template (after line 114, before Task Context)**

Insert before `## Task Context`:

```text
## Rotation

After your task completes, you will likely become the NAVIGATOR for the next task.
The lead will tell you when this happens via SendMessage. When you rotate to navigator:
- Stop editing code files. Your job becomes reading and advising.
- Send typed advice to the new driver instead of making changes.
- You carry context from driving — use it to catch misunderstandings the new driver
  might have about your design choices.

Rotation is mandatory. Don't recommend yourself for the next task — the lead handles
assignment based on rotation.
```

- [ ] **Step 6: Update driver Important section (lines 101-114)**

Add after line 112 ("If you get stuck..."):

```text
- Rotation is mandatory. After your task, the navigator becomes the next driver.
  Don't recommend yourself for the next task.
- If you receive a shutdown_request message, approve it immediately. Do not send
  more task content. The session is over.
```

- [ ] **Step 7: Update navigator advice instruction (lines 143-146)**

Replace:
```text
   c. If you find something worth raising, send typed advice via SendMessage to
      "{driver_name}". Use the format from the Advice Format section below.
   d. Append the same advice to .popcorn-xp/ADVICE.md under "## Open".
```

with:
```text
   c. If you find something worth raising, send typed advice via SendMessage to
      "{driver_name}". Start your message with the type and ID (see Advice Format).
      ADVICE.md is updated automatically from your message — do not edit it directly.
```

- [ ] **Step 8: Update navigator OBJECTION handling (lines 160-162)**

Replace:
```text
   a. Wait for the driver's response (fix or reject).
   b. If rejected with sound reasoning, accept it — the system worked.
   c. When resolved, append a resolution entry to ADVICE.md under "## Resolved".
```

with:
```text
   a. Wait for the driver's response (fix or reject).
   b. If rejected with sound reasoning, accept it — the system worked.
   c. Resolution is logged automatically when the driver sends a RESOLVE message.
```

- [ ] **Step 9: Update navigator Important section (lines 203-206)**

Replace:
```text
- You are the navigator, not a second driver. Do not edit code files.
- Your tools should be read-oriented: Read, Grep, Glob, Bash (for read-only commands).
```

with:
```text
- While navigating, do not edit code files — read and advise only.
  (You may be rotated to driver for the next task, with full edit permissions.)
- Your tools should be read-oriented: Read, Grep, Glob, Bash (for read-only commands).
```

- [ ] **Step 10: Add rotation section to navigator template (after line 221, before Task Context)**

Insert before `## Task Context`:

```text
## Rotation

After this task completes, you will likely become the DRIVER for the next task —
you've been watching the code emerge and carry the most context. The lead will tell
you when this happens via SendMessage. When you rotate to driver:
- You now have FULL EDIT PERMISSIONS. Read, write, create, delete files.
- Mark your new task in_progress with TaskUpdate and start working.
- Send checkpoints to your new navigator (the previous driver).
- Your read-ahead knowledge from navigating becomes your implementation advantage.
```

- [ ] **Step 11: Add shutdown and navigator idle guidance to navigator Important**

Add after line 218 ("Only go idle after..."):

```text
- If you've exhausted proactive reading on a small task: review test files for
  coverage gaps, check adjacent code for patterns, or tell the driver "I've read
  ahead, nothing to flag — send checkpoints and I'll review in real-time."
- If you receive a shutdown_request message, approve it immediately. The session
  is over.
```

- [ ] **Step 12: Update advisor template LOG.md reference (line 251)**

Replace:
```text
5. Append your findings to .popcorn-xp/LOG.md.
```

with:
```text
5. Your findings are logged automatically when you send messages with checkpoint
   or advice format markers.
```

- [ ] **Step 13: Add "Resolving Advice" section to Advice Format (after line 304)**

Insert after the ID Convention section:

```text
### Resolving Advice

When you've decided what to do with advice, send a resolution message:

```
RESOLVE {ID} {OUTCOME}: {detail}
```

Outcomes:
- `FIXED` — you fixed the issue: "RESOLVE OBJ-3-01 FIXED: Added depth guard at line 48"
- `REJECTED` — you disagree: "RESOLVE OBJ-3-01 REJECTED: Upstream caller validates depth"
- `INCORPORATED` — you used the suggestion: "RESOLVE STR-3-01 INCORPORATED: Using Set for O(1)"
- `NOTED` — acknowledged: "RESOLVE FYI-1-01 NOTED"

ADVICE.md is updated automatically from this message. REJECTED is a first-class outcome.
```

- [ ] **Step 14: Simplify the ADVICE.md Format section (lines 306-348)**

Replace the entire "### ADVICE.md Format" section (lines 306-348) with:

```text
### ADVICE.md Format

ADVICE.md is populated automatically by hooks. You do not need to edit it directly
for creating advice or logging resolutions — just use SendMessage with the formats
above, and the system handles persistence.

You should still READ ADVICE.md:
- Before starting a task — check for open advice from prior rounds
- Before completing a task — ensure no open OBJECTIONs remain
- When waking from idle — catch up on what happened while you were away

The file uses this structure (populated by hooks):

```markdown
# Popcorn XP Advice

## Open

### SMELL SML-2-01 — to @craftsman
SMELL SML-2-01: topoSort uses O(n) indexOf
File: demo/task-runner.js:64
Observation: path.indexOf called on every visit
- Status: open

## Resolved

### SML-2-01 — INCORPORATED
- Detail: Added visiting Set for O(1) detection
```

Do not edit the original entry under ## Open. Resolution entries accumulate
under ## Resolved. The hooks enforce that OBJECTIONs in ## Open block task completion.
```

- [ ] **Step 15: Commit protocol.md changes**

```bash
git add references/protocol.md
git commit -m "refactor: remove dual-write from protocol, add rotation awareness

Driver/navigator templates no longer instruct agents to manually write
to ADVICE.md or LOG.md — hooks handle persistence from SendMessage.

Added rotation sections to both templates so agents know they'll swap
roles. Softened navigator's 'do not edit' to 'while navigating' so
rotation doesn't fight the original prompt identity.

Removed driver self-recommendation. Added shutdown awareness.
Added 'Resolving Advice' format for hook-driven resolution logging."
```

---

## Task 5: Update SKILL.md and agent definitions

Lighter edits: add verification task guidance, update lead's code-reviewer note, add rotation awareness to agent definitions.

**Files:**
- Modify: `SKILL.md:148-150` (verification task guidance)
- Modify: `SKILL.md:210-214` (code-reviewer note)
- Modify: `SKILL.md:225-230` (shutdown pattern)
- Modify: `agents/expert.md:42-43`
- Modify: `agents/craftsman.md:42-43`

- [ ] **Step 1: Add verification task guidance to SKILL.md (after line 150)**

Insert after "Include enough context in each task description...":

```text
**When to include a separate verification task:**
- A different agent runs verification than wrote the code (fresh eyes)
- Integration or E2E tests that weren't part of the unit test task
- Verification requires a different environment (staging, browser, device)

**When to fold verification into the last task's exit criteria:**
- Same agent would re-run the same tests
- The test-writing task already runs all tests
- The project is small enough that "run tests" takes seconds

Don't create thin verification tasks just to have 4 tasks. 3 well-scoped tasks
are better than 4 where the last one is "run tests again."
```

- [ ] **Step 2: Update code-reviewer independence note in SKILL.md (after line 214)**

Insert after "The code-reviewer never messages teammates directly — you are the relay.":

```text
  **Note:** The Agent tool may auto-inherit team_name from the lead's session. The
  code-reviewer functions correctly despite this — it does not use SendMessage,
  TaskUpdate, or team coordination tools. Its independence is behavioral (enforced
  by its prompt), not structural.
```

- [ ] **Step 3: Update shutdown pattern in SKILL.md (lines 225-230)**

Replace:
```text
5. Shut down teammates. Send each a shutdown_request individually (broadcast does not support structured messages):
   ```
   SendMessage(to: "craftsman", message: {type: "shutdown_request"})
   SendMessage(to: "expert", message: {type: "shutdown_request"})
   ```
   If a teammate cycles idle without acknowledging the shutdown after 2 attempts, send a plain-text message telling them the session is over and to approve the pending shutdown request. If they still don't respond after a third attempt, move on — they will be cleaned up by TeamDelete.
```

with:
```text
5. Shut down teammates. For each teammate, send a plain-text heads-up followed by
   the structured request — the plain text primes them to accept:
   ```
   SendMessage(to: "craftsman", summary: "session over", message: "Session is over. Approve the shutdown request that follows.")
   SendMessage(to: "craftsman", message: {type: "shutdown_request"})
   ```
   If a teammate doesn't acknowledge after 2 attempts, move on — TeamDelete cleans up.
```

- [ ] **Step 4: Add rotation awareness to agents/expert.md**

Insert after line 43 ("You are often the navigator during implementation.") in `agents/expert.md`:

```text
When rotated to driver, your edge-case knowledge becomes your implementation advantage —
you already know where the code is fragile and what inputs will break it.
```

- [ ] **Step 5: Add rotation awareness to agents/craftsman.md**

Insert after line 43 ("You are often the first driver for implementation tasks.") in `agents/craftsman.md`:

```text
When rotated to navigator, your implementation knowledge becomes your review advantage —
you know the design intent behind every decision and can catch misunderstandings.
```

- [ ] **Step 6: Commit SKILL.md and agent definition changes**

```bash
git add SKILL.md agents/expert.md agents/craftsman.md
git commit -m "refactor: add verification guidance, rotation awareness, shutdown pattern

SKILL.md: guidance for when verification is its own task vs. folded into
the last task. Code-reviewer independence note. Two-part shutdown pattern.

Agent definitions: expert and craftsman now mention rotation so they
expect to swap roles mid-session."
```

---

## Task 6: Write the final hooks.json and verify integration

Assemble the complete hooks.json with all new and existing hooks registered correctly.

**Files:**
- Modify: `hooks/hooks.json` (final assembly — ensure all hooks from tasks 1-3 are registered)

- [ ] **Step 1: Write the complete hooks.json**

The file should contain all hooks — existing (fixed) and new:

```json
{
  "description": "Popcorn XP lifecycle hooks — advice enforcement, rotation checks, checkpoint tracking, and retro gating",
  "hooks": {
    "TaskCompleted": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/check-advice-on-complete.sh",
            "timeout": 10,
            "statusMessage": "Checking advice before task completion..."
          },
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/check-rotation.sh",
            "timeout": 10,
            "statusMessage": "Checking driver rotation..."
          }
        ]
      }
    ],
    "SubagentStop": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/check-objections.sh",
            "timeout": 10
          }
        ]
      }
    ],
    "TeammateIdle": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/remind-unread-advice.sh",
            "timeout": 10
          },
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/remind-checkpoint.sh",
            "timeout": 5
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "TeamDelete",
        "hooks": [
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/check-retro-before-delete.sh",
            "timeout": 10,
            "statusMessage": "Checking for retrospective..."
          }
        ]
      },
      {
        "matcher": "Edit",
        "hooks": [
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/mark-dirty.sh",
            "timeout": 5
          }
        ]
      },
      {
        "matcher": "Write",
        "hooks": [
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/mark-dirty.sh",
            "timeout": 5
          }
        ]
      },
      {
        "matcher": "TaskUpdate",
        "hooks": [
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/init-session.sh",
            "timeout": 5
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "SendMessage",
        "hooks": [
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/auto-log-messages.sh",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 2: Validate hooks.json is valid JSON**

Run: `jq . hooks/hooks.json > /dev/null && echo "valid" || echo "invalid"`
Expected: "valid"

- [ ] **Step 3: Verify all referenced scripts exist and are executable**

Run:
```bash
for script in hooks/scripts/*.sh; do
  echo "$script: $(test -x "$script" && echo "executable" || echo "NOT executable")"
done
```
Expected: All scripts show "executable"

- [ ] **Step 4: Count hooks — should be 9 total**

Run:
```bash
grep -c '"command":' hooks/hooks.json
```
Expected: 9 (check-advice-on-complete, check-rotation, check-objections, remind-unread-advice, remind-checkpoint, check-retro-before-delete, mark-dirty x2 matchers but 1 script, init-session, auto-log-messages)

Actually the count of `"command":` lines should be 10 (mark-dirty appears twice — once for Edit, once for Write).

- [ ] **Step 5: Commit final hooks.json**

```bash
git add hooks/hooks.json
git commit -m "chore: finalize hooks.json with all new and fixed hooks

9 hook scripts across 5 lifecycle events:
- TaskCompleted: advice check + rotation check (fixed)
- SubagentStop: objection backup block
- TeammateIdle: advice reminder (fixed wording) + checkpoint reminder (new)
- PreToolUse: retro gate, edit/write dirty tracking (new), session init (new)
- PostToolUse: SendMessage auto-logging (new)"
```

---

## Self-Review Checklist

**Spec coverage:**
- [x] P0 bug: check-rotation.sh hardcoded path → Task 1 steps 1-2
- [x] P0 bug: remind-unread-advice.sh wording → Task 1 steps 3-4
- [x] Auto-log advice from SendMessage → Task 2
- [x] Auto-log checkpoints from SendMessage → Task 2
- [x] Auto-log resolutions from SendMessage → Task 2
- [x] Checkpoint enforcement (dirty flag + reminder) → Task 3
- [x] Session auto-init → Task 3
- [x] Remove dual-write from driver template → Task 4 steps 1, 4
- [x] Remove dual-write from navigator template → Task 4 steps 7-8
- [x] Add rotation sections to both templates → Task 4 steps 5, 10
- [x] Remove driver self-recommendation → Task 4 step 3
- [x] Soften navigator edit prohibition → Task 4 step 9
- [x] Add shutdown awareness → Task 4 steps 6, 11
- [x] Add RESOLVE message format → Task 4 step 13
- [x] Simplify ADVICE.md format section → Task 4 step 14
- [x] Verification task guidance → Task 5 step 1
- [x] Code-reviewer independence note → Task 5 step 2
- [x] Two-part shutdown pattern → Task 5 step 3
- [x] Agent rotation awareness → Task 5 steps 4-5

**Placeholder scan:** No TBD/TODO/placeholders. All code blocks are complete.

**Type consistency:** Hook script names, format markers (OBJECTION/SMELL/STEER/FYI), ID patterns (OBJ-X-XX), RESOLVE format — all consistent across tasks.
