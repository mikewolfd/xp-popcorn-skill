# Shutdown Lifecycle Enforcement

**Date:** 2026-04-02
**Status:** Approved
**Goal:** Mechanically enforce retro submission before shutdown and reliable teammate termination via signal files and TeammateIdle hook phases.

**Problem:** Across two sessions, teammates ignored retro requests (responding with task status instead of process observations) and ignored shutdown_request messages (idle-looping indefinitely). The lead had to write retros from its own observations alone and rely on TeamDelete to force cleanup. R2 (retro instructions in protocol) addresses the informational gap but cannot enforce compliance. A mechanical backstop is needed.

---

## Architecture

### Phase model

The TeammateIdle hook (`enforce-no-idle.sh`) detects session phase via signal files in `.popcorn-xp/{team}/`:

| Phase | Signal files present | Hook behavior | Exit |
|-------|---------------------|---------------|------|
| **Working** | neither `.retro-requested` nor `.shutdown` | Nudge: "Go find work" (current behavior) | `exit 2` (stderr) |
| **Retro pending** | `.retro-requested`, no `.retro-{agent}.md` | Nudge: "Submit your retro via session script" | `exit 2` (stderr) |
| **Retro submitted** | `.retro-requested` + `.retro-{agent}.md` | Allow idle (waiting for shutdown signal) | `exit 0` |
| **Shutdown** | `.shutdown` | Force-stop teammate | `exit 0` (stdout JSON `{"continue": false}`) |

The hook reads `teammate_name` from the TeammateIdle input JSON (provided by the platform) to determine which agent's retro file to check.

Phase transitions are controlled entirely by the lead writing signal files via the session script. Teammates cannot advance the phase — they can only respond to it.

### Signal files

All signal files live in `.popcorn-xp/{team}/`:

| File | Written by | Purpose |
|------|-----------|---------|
| `.retro-requested` | Lead via `session retro-request` | Signals retro phase has begun |
| `.retro-{agent}.md` | Teammate via `session retro {agent} 'feedback'` | Contains that agent's retro observations |
| `.shutdown` | Lead via `session shutdown` | Signals force-stop on next idle |

### Decision flow

```
TeammateIdle fires
  → .shutdown exists?
      YES → stdout: {"continue": false, "stopReason": "..."}, exit 0
  → .retro-requested exists?
      YES → .retro-{agent}.md exists?
          YES → exit 0 (allow idle, retro done, waiting for shutdown)
          NO  → stderr: "submit retro", exit 2
  → DEFAULT → stderr: "go find work", exit 2
```

Shutdown is checked first so the lead can force-stop even if retro was skipped (escape hatch for stuck sessions).

---

## Components

### 1. Session script — new subcommands

Add three subcommands to the `session` helper in `skills/popcorn-xp/SKILL.md`:

```bash
retro-request) touch "$DIR/.retro-requested" ;;
retro) AGENT="${1:?}"; shift; printf '%s\n' "$*" > "$DIR/.retro-$AGENT.md" ;;
shutdown) touch "$DIR/.shutdown" ;;
```

- `retro-request`: Lead signals retro phase.
- `retro AGENT "feedback text"`: Teammate writes retro observations to a per-agent file.
- `shutdown`: Lead signals force-stop.

### 2. enforce-no-idle.sh — rewrite with phase chain

Replace the current unconditional "go find work" script with phase-aware logic:

```bash
#!/bin/bash
set -euo pipefail

# enforce-no-idle.sh
# TeammateIdle hook: phase-aware idle enforcement.
#
# Phases (checked in priority order):
# 1. Shutdown: .shutdown exists → force-stop teammate
# 2. Retro pending: .retro-requested exists, .retro-{agent}.md missing → nudge retro
# 3. Retro done: .retro-requested + .retro-{agent}.md exist → allow idle
# 4. Working: default → nudge "go find work"
#
# No-op when no active popcorn-xp session.

POPCORN_DIR="${CLAUDE_PROJECT_DIR:-.}/.popcorn-xp"
TEAM=$(cat "$POPCORN_DIR/.active-team" 2>/dev/null || true)
[ -z "$TEAM" ] && exit 0

TEAM_DIR="$POPCORN_DIR/$TEAM"
[ ! -d "$TEAM_DIR" ] && exit 0

# Read teammate_name from stdin (TeammateIdle input)
INPUT=$(cat)
AGENT=$(echo "$INPUT" | jq -r '.teammate_name // empty' 2>/dev/null || true)

# Phase 1: Shutdown — force-stop
if [ -f "$TEAM_DIR/.shutdown" ]; then
  echo '{"continue": false, "stopReason": "Session complete — lead initiated shutdown"}'
  exit 0
fi

# Phase 2/3: Retro
if [ -f "$TEAM_DIR/.retro-requested" ]; then
  if [ -n "$AGENT" ] && [ ! -f "$TEAM_DIR/.retro-$AGENT.md" ]; then
    # Phase 2: Retro pending — nudge
    echo "Popcorn XP: Retro time. Submit your process observations now: .popcorn-xp/$TEAM/session retro $AGENT 'What worked? What didn't? What would you change about the process?'" >&2
    exit 2
  fi
  # Phase 3: Retro submitted — allow idle, waiting for shutdown
  exit 0
fi

# Phase 4: Working — go find work
echo "Popcorn XP: Agents must never idle. If you're waiting, pick something productive: review the task description, read ahead in relevant files, check ADVICE.md for unresolved items, or investigate the next problem. Idle time is wasted pairing time." >&2
exit 2
```

### 3. hooks.json — remove unsupported matchers

Remove `matcher: "*"` from TeammateIdle, TaskCompleted, and SubagentStop entries. The official docs state these events don't support matchers — the field is silently ignored. Removing it makes the config accurate.

Before:
```json
"TeammateIdle": [{ "matcher": "*", "hooks": [...] }]
"TaskCompleted": [{ "matcher": "*", "hooks": [...] }]
"SubagentStop": [{ "matcher": "*", "hooks": [...] }]
```

After:
```json
"TeammateIdle": [{ "hooks": [...] }]
"TaskCompleted": [{ "hooks": [...] }]
"SubagentStop": [{ "hooks": [...] }]
```

### 4. Lead SKILL.md — updated Verify and Close sequence

Steps 4-5 of Verify and Close change from the current "ask via SendMessage and hope" to a mechanical flow:

**Step 4: Retrospective (mandatory)**

1. Run `session retro-request` to signal retro phase.
2. SendMessage each teammate: "Retro time — submit your process observations via `.popcorn-xp/{team}/session retro {your-name} 'your feedback'`"
3. The TeammateIdle hook now mechanically nudges agents on every idle cycle until they comply.
4. Wait until `.retro-{agent}.md` files exist for each active teammate (check via `ls .popcorn-xp/{team}/.retro-*.md`).
5. Read each `.retro-{agent}.md` file to incorporate teammate perspectives into RETRO.md.

**Step 5: Shutdown**

1. Run `session shutdown` to write the `.shutdown` signal file.
2. Agents are force-stopped on their next idle cycle via `{"continue": false}`.
3. No need to send `shutdown_request` messages or wait for acknowledgment.
4. Proceed to TeamDelete after agents stop.

This replaces the current pattern of sending shutdown_request, waiting, retrying, and eventually giving up.

### 5. Protocol SKILL.md — teammate retro instructions

Update the Retro section to include the session script command:

> When you receive a retro request, submit your observations using the session script:
> ```
> .popcorn-xp/{team}/session retro {your-name} 'What worked? What didn't? ...'
> ```

Update the Integration Notes shutdown line to remove "approve shutdown_request promptly" — agents no longer need to acknowledge shutdown. Replace with:

> On session close, the lead signals shutdown mechanically. Submit your retro when asked — the session cannot close until you do.

### 6. Tests

Add to `tests/test-hooks.sh`:

**Phase tests for enforce-no-idle.sh:**
- No session: exits 0 (no-op)
- Working phase (no signal files): exits 2, stderr contains "never idle"
- Retro requested, no retro file: exits 2, stderr contains "retro" and agent name
- Retro requested + retro file exists: exits 0
- Shutdown: exits 0, stdout contains `{"continue": false}`
- Shutdown overrides retro-pending (both present): exits 0 with force-stop

**Session script tests:**
- `session retro-request` creates `.retro-requested`
- `session retro agent-name 'feedback'` creates `.retro-agent-name.md` with content
- `session shutdown` creates `.shutdown`

---

## Data flow

```
Lead                          Signal files              TeammateIdle hook           Teammate
─────                         ────────────              ─────────────────           ────────
all tasks done
  │
  ├─ session retro-request ──→ .retro-requested
  ├─ SendMessage "retro time"                                                    ──→ receives msg
  │                                                     idle fires
  │                                                       checks .retro-requested
  │                                                       checks .retro-{agent}.md
  │                                                       missing → stderr nudge  ──→ "submit retro"
  │                                                                                    │
  │                           .retro-{agent}.md  ←──────────────────────────────────── session retro
  │                                                     idle fires
  │                                                       .retro-{agent}.md exists
  │                                                       exit 0 (allow idle)
  ├─ reads .retro-*.md
  ├─ writes RETRO.md
  ├─ session shutdown ───────→ .shutdown
  │                                                     idle fires
  │                                                       .shutdown exists
  │                                                       {"continue": false}     ──→ force-stopped
  ├─ TeamDelete
```

---

## Error handling

- **Agent name missing from input JSON**: If `teammate_name` is empty (shouldn't happen per docs, but defensive), fall through to working phase (exit 2 with "go find work"). Agent gets nudged but not stuck.
- **Lead skips retro-request**: If lead writes `.shutdown` without `.retro-requested`, agents are force-stopped immediately. This is the escape hatch for stuck sessions.
- **Agent never submits retro**: TeammateIdle nudges indefinitely until the lead writes `.shutdown`. The lead can decide to skip after N cycles.
- **Multiple idle hooks**: `remind-unread-advice.sh` and `remind-checkpoint.sh` still fire alongside `enforce-no-idle.sh`. In retro/shutdown phases, these other hooks may also fire exit 2 nudges. The docs don't specify how conflicting TeammateIdle results are resolved when one hook returns `{"continue": false}` and another returns exit 2. **Mitigation:** `remind-checkpoint.sh` already clears `.dirty` and `.edit-count` on fire, so it's self-limiting. `remind-unread-advice.sh` only fires when there's unread advice. If the force-stop doesn't take effect due to a competing exit 2, it will fire again on the next idle cycle — convergence is guaranteed because the shutdown signal is persistent.

## Files affected

| File | Change |
|------|--------|
| `hooks/scripts/enforce-no-idle.sh` | Rewrite: phase-aware idle enforcement |
| `hooks/hooks.json` | Remove `matcher: "*"` from TeammateIdle, TaskCompleted, SubagentStop |
| `skills/popcorn-xp/SKILL.md` | Add `retro-request`, `retro`, `shutdown` subcommands to session script template |
| `skills/popcorn-xp-protocol/SKILL.md` | Update Retro section with session script command; update Integration Notes |
| `skills/popcorn-xp/SKILL.md` | Update Verify and Close steps 4-5 with new mechanical flow |
| `tests/test-hooks.sh` | Add phase tests for enforce-no-idle.sh and session script subcommands |
| `docs/improvement-backlog.md` | Add R4 entry for this work |
