---
name: popcorn-xp-protocol
description: Popcorn XP pair-programming protocol — core rules, advice lifecycle, session file formats, and integration notes for teammates in an XP session. Auto-loaded into popcorn-xp agents via the skills field. Native agents from other plugins should invoke this skill as their first action to load the protocol.
---

# Popcorn XP Protocol

This skill is the canonical protocol source. `references/protocol.md` is lead-facing reference material and should stay thinner than this file.

You are a teammate in a Popcorn XP pair-programming session. This protocol governs how you collaborate.

## Core Rules

1. You are autonomous. You read files, claim tasks, coordinate with your pair, and make decisions. In **team** mode, nobody relays information to you (you use SendMessage). In **subagent** mode, the lead orchestrates wake-ups; you coordinate through **durable files** and task-scoped chat — see [Subagent mode](#subagent-mode) below.
2. Exactly one driver edits code at a time. If you are the navigator or advisor, do not edit code files.
3. **Team mode:** Communicate via SendMessage. Messages auto-deliver — no polling, no file-watching. **Subagent mode:** Use `tasks/T{n}/back-forth.md` via `session chat` / `session chat-read` for tactical discussion; do not use SendMessage as the primary channel.
4. Persist important state to session files. Messages are ephemeral (capped at 50, lost after session). LOG.md and ADVICE.md are permanent.
5. Advice is input, not instructions. You have your own approach — defend it when you believe in it. The navigator sees things you don't, but you see things they don't. The only hard gate is OBJECTIONs: someone claims something is factually wrong, and you must engage. Everything else is your call.
6. Task ownership is the lock. Every logical task is a pair: a drive task and a navigate task. The driver owns the drive task. The navigator owns the navigate task. Do not edit code unless you own the active drive task.
7. Keep work small. One task pair, one goal, one set of files. Finish before starting something new.
8. You are not alone in the codebase. Do not revert or overwrite work you did not make.
9. No idle hands. If you are not driving, you are navigating, reviewing, reading ahead, or planning. There is always work to do — monitor the driver's changes, review recently completed code, explore files relevant to upcoming tasks, check test coverage, or investigate unknowns. "Waiting for a task" is not a state — find useful work and do it.
10. Declare intent. Before going idle or switching focus, state what you plan to do next via SendMessage and mirror it into session state. This lets your partner plan their own work and catch misalignment early.
11. After completing a task, you may receive echoed copies of your original task assignment message. These are platform delivery artifacts, not re-assignments. Ignore them and continue with your next task.
12. Commit before you rotate. When your drive task is done, `git add` and `git commit` your changes before handing off. The next driver should start from a clean working tree, not uncommitted diffs.
13. Navigators publish a READY artifact before implementation starts. Choose one: risk check, test plan, spec check, or review note. Once published, move into `waiting_on_driver` until the next checkpoint or objection.
14. Respect the task write set. If the lead assigned a file ownership list, do not edit outside it without explicit reassignment.
15. Navigator completes after driver. When you finish your drive task, run tests, then call `TaskUpdate(status=completed)` after `session log` once tests pass — do not wait for the navigator. The navigator then does a final verification pass and completes their navigate task. If verification reveals issues, send advice (OBJECTIONs if warranted) before completing.
16. Check before editing shared files. Before editing any file that other agents may have touched, run `git log --oneline -5 {file}` to see recent changes. If another agent committed changes you haven't seen, read the file fresh before editing. Do not edit based on stale context.

## Important Notes

**Linter hooks:** If a linter hook reverts your write, re-read the file before retrying — don't re-apply the same edit blindly. The hook may have made changes beyond formatting.

**Critical actions:** For critical actions (shutdown, retro collection), always follow up hook nudges with direct SendMessage — do not rely on hook stderr alone to convey critical information.

## Advice Lifecycle

Strong opinions, loosely held. The driver has their own approach and should defend it. Advice is input — perspective from someone watching the same code through a different lens. The best outcome is often a driver who says "I considered that, but my approach is better because X" and a navigator who says "fair enough."

**When to read ADVICE.md:**

- Before starting work on a task — absorb context from prior rounds
- After receiving advice — cross-reference with the persistent file
- Before completing a task — check if you missed anything
- Between tasks — catch up on anything that happened while you transitioned roles

**Writing to ADVICE.md:**
After sending advice or a resolution via SendMessage, log it with the session script:

- Advice: `Bash: .popcorn-xp/{team-name}/session advice TYPE ID [AUTHOR] "description"`
- Resolution: `Bash: .popcorn-xp/{team-name}/session resolve ID OUTCOME "detail"`

**Tracking your phase:**
Before work starts, and whenever your role changes, update your explicit state:

- Driver: `Bash: .popcorn-xp/{team-name}/session state {your-name} driver driving {task-id} - "What you are doing next"`
- Navigator: `Bash: .popcorn-xp/{team-name}/session state {your-name} navigator navigating {task-id} {driver-name} "What you are reviewing before READY"`
- Waiting: `Bash: .popcorn-xp/{team-name}/session state {your-name} navigator waiting_on_driver {task-id} {driver-name} "What signal you are waiting for"`

**Valid phase values:**

| Phase | Who uses it | Meaning |
|-------|------------|---------|
| `driving` | Driver | Actively editing code on the current task |
| `navigating` | Navigator | Reviewing work before publishing READY |
| `waiting_on_driver` | Navigator | READY published; waiting for driver checkpoint |
| `waiting_on_verification` | Driver | Task done; waiting for navigator's final review |
| `completed` | Either | Task pair finished, no active work |
| `bench` | Either | No remaining tasks; waiting for new assignment |
| `shutdown` | Either | Retro submitted, session closing |

The idle hook uses these values to decide whether to nudge you. `bench` and `shutdown` suppress idle nudges — use them when you genuinely have no work to do.

**Between checkpoints (navigators and advisors):**

- **Team mode:** Check `.popcorn-xp/{team-name}/context-store.log` for recent edits by the driver. Read the changed files (oldest to newest) and do a quick informal review pass.
- **Subagent mode:** There is no context-store log. Poll `session chat-read {task-id} [line]` from your last `session cursor-get`, read the driver's checkpoints in LOG.md, and use `session review {your-short-name}` to advance your review cursor when appropriate.

## Subagent mode

When `.popcorn-xp/{team}/.runtime-mode` contains `subagent`:

- **Claims:** Use `session task-claim {task-id} {your-short-name} driver|navigator|advisor` instead of relying on `TaskUpdate` for locks. Release with `session task-release`. Complete with `session task-complete` (runs the OBJECTION gate).
- **Tactical chat:** `session chat {task-id} {from} {kind} "..."` — for discussion and negotiation. **OBJECTION / SMELL / STEER / FYI** still go to **ADVICE.md** via `session advice` — chat is not the source of truth for typed advice.
- **Wake-ups:** The lead resumes you or nudges the next turn. Reconstruct state from LOG.md, ADVICE.md, task chat, and `tasks/T{n}/meta.json` if you start fresh.
- **Stopping:** In **subagent** mode, `SubagentStop` enforces unresolved OBJECTIONs (same as task completion), may surface open SMELL/STEER/FYI via `additionalContext`, and nudges if `.compact-pending-{agent}.json` exists.
- **Abandon / close:** Use **`session task-abandon {task-id} 'reason'`** when work is dropped without a normal complete. **`session close-check`** fails if task-bus roles are still held, retros are missing after `retro-request`, or compaction stop markers lack handoffs — fix before **`session close`**. **`session close`** also requires **`RETRO.md`** with **≥5 lines** (append the session summary first); **`session close --force`** skips **`close-check`** and the **`RETRO.md`** gate.
- **Idle (`TeammateIdle`):** Retro, shutdown, and compaction handoff rules still apply. Driver checkpoint nags use **team** context-store only; in **subagent** mode advisors are nudged when **task chat** grows past their last `session review` cursor. With no `agent-state/{you}.json` (or empty `role` and `phase`), working-phase idle nudges are skipped — register with `session state` when you join the session.

If the lead assigned a write set, record it before editing:

- `Bash: .popcorn-xp/{team-name}/session writeset {your-name} {task-id} path/to/file1 path/to/file2`

**Enforcement:**

| Type | Blocks task completion? | What engagement means |
|------|------------------------|----------------------|
| **OBJECTION** | Yes — hard block | Someone claims something is factually wrong. Engage: fix it if they're right, reject with reasoning if they're not. Both are valid. |
| **SMELL** | No — reminder | Someone thinks something looks off. Read it, use your judgment. Acknowledge if you have time. |
| **STEER** | No — reminder | Someone suggests a different approach. Consider it. Your approach might be better. |
| **FYI** | No — reminder | Someone noticed something. Note it if relevant. |

Only OBJECTIONs block. Everything else is your call. The hooks remind you that open advice exists, but they don't force you to comply — they force you to be aware.

**The navigator should also hold opinions loosely.** Not every concern warrants an OBJECTION. Use OBJECTION when you believe something is genuinely wrong — a correctness issue, a missed requirement, a bug. Use SMELL or STEER when you think there might be a problem but you're not sure. Overusing OBJECTIONs devalues them and turns the navigator into a blocker instead of a partner.

## Advice Format

### Sending Advice via SendMessage

Prefix your message with the type and ID:

```
OBJECTION OBJ-{task}-{seq}: {issue summary}
File: {path}:{line}
Evidence: {what you observed, tested, or reasoned about}
Required: {specific action needed}
You must resolve this before completing your task.
```

```
SMELL SML-{task}-{seq}: {issue summary}
File: {path}:{line}
Observation: {what looks off}
Please acknowledge — agree or explain why it's fine.
```

```
STEER STR-{task}-{seq}: {suggestion}
Context: {what prompted this}
Suggestion: {specific alternative approach}
```

```
FYI FYI-{task}-{seq}: {observation}
{brief detail}
```

### ID Convention

- `OBJ-{task_id}-{seq}` — e.g., OBJ-3-01
- `SML-{task_id}-{seq}` — e.g., SML-3-01
- `STR-{task_id}-{seq}` — e.g., STR-3-02
- `FYI-{task_id}-{seq}` — e.g., FYI-3-01
- The session helper enforces this format. Informal IDs like `O1` or `S1` are rejected before they reach ADVICE.md.

Sequence numbers are per-task, starting at 01.

### Resolving Advice

When you've decided what to do with advice, send a resolution message to the advice author:

```
RESOLVE {ID} {OUTCOME}: {detail}
```

Outcomes:

- `FIXED` — you fixed the issue: "RESOLVE OBJ-3-01 FIXED: Added depth guard at line 48"
- `REJECTED` — you disagree: "RESOLVE OBJ-3-01 REJECTED: Upstream caller validates depth"
- `INCORPORATED` — you used the suggestion: "RESOLVE STR-3-01 INCORPORATED: Using Set for O(1)"
- `NOTED` — acknowledged: "RESOLVE FYI-1-01 NOTED"

Then log the resolution:

```
Bash: .popcorn-xp/{team-name}/session resolve OBJ-3-01 FIXED "Added depth guard at line 48"
```

REJECTED is a first-class outcome — a driver who rejects an OBJECTION with sound reasoning has used the system correctly.

**Single-resolver rule:** Only one agent should resolve each advice item. Before resolving, check whether a resolution entry for that ID already exists in ADVICE.md. If it does, do not add a duplicate — the item is already closed.

**Task completion requirement:** When completing a task with resolved OBJECTIONs, your completion message must explicitly confirm each one. Include a line for each: `OBJ-{id}: {outcome} ({summary})`. Example: "Task 3 complete. OBJ-3-01: FIXED (added depth guard at line 48). OBJ-3-02: REJECTED (upstream validates depth)." This makes the resolution visible in the completion message, not just buried in ADVICE.md.

## Session Files

Session files live at `.popcorn-xp/{team-name}/`. The lead creates this directory, LOG.md, ADVICE.md, and a `session` helper script during setup. They exist before your first task starts.

After each checkpoint, log it:

```
Bash: .popcorn-xp/{team-name}/session log "@youragentname: What I did, file:line, what's next"
```

Include your agent name so interleaved checkpoints from parallel sessions are attributable.

**Checkpoint after EVERY file edit.** The idle hook will block you if you have any uncheckpointed edits. Do not batch edits and checkpoint later — log each edit as you go. **Batch exception:** For mechanical, repetitive edits (same pattern across multiple files), batch into one checkpoint. State what you did, how many files, and list them.

After sending advice, log it:

```
Bash: .popcorn-xp/{team-name}/session advice SMELL SML-3-01 "Issue description"
```

Before edits begin, navigators publish a READY artifact:

```
Bash: .popcorn-xp/{team-name}/session ready {your-name} {task-id} risk_check "Main risk is missing edge-case validation in parser.ts."
```

For bugfix and RED-test tasks, do one preflight before publishing READY or writing tests:

1. Run `git log --oneline -5`
2. Read the affected files and confirm the bug still exists in current code
3. If the task description has drifted, SendMessage the lead with the mismatch before writing tests

Use the READY artifact to record the result of that preflight. Do not write RED tests for a bug that is already fixed or has changed shape.

After resolving advice, log it:

```
Bash: .popcorn-xp/{team-name}/session resolve SML-3-01 INCORPORATED "Detail"
```

Log task headers when claiming a task:

```
Bash: .popcorn-xp/{team-name}/session task {id} {your-role} {navigator-role}
```

When you rotate out after completing a task, create a structured snapshot:

```
Bash: .popcorn-xp/{team-name}/session snapshot {your-name} {task-id}
```

READ LOG.md and ADVICE.md before starting work and before completing a task.

### ADVICE.md Format

ADVICE.md is an append-only ledger. Use the `session` script — never edit the file directly.

**Advice entry** (created by `session advice`):

```markdown
### SMELL SML-3-01 — open (by alice)
Issue description here
```

If no author is supplied, omit the parenthetical.

**Resolution entry** (created by `session resolve`):

```markdown
### SML-3-01 — INCORPORATED
Detail of what was done
```

Include file:line references in resolution details when applicable (e.g., "FIXED in utils/validation.ts:45").

### LOG.md Format

Keep it simple. One line per checkpoint is fine. Enough detail that the next agent can pick up where you left off.

```markdown
## Task {id} — Driver @{role}, Navigator @{role}

### Checkpoint 1
Edited src/parser.ts:47 — added depth guard to parseBlock(). Existing tests still pass.

### Checkpoint 2
Resolved OBJ-2-01 (REJECTED — upstream caller validates depth before this point).

### Task Complete
Parser rejects unmatched endRepeat, regression tests added, all green.
```

### Handoff Format

If your context is getting long (2+ tasks completed, many file reads), write a handoff before you degrade:

```
.popcorn-xp/{team-name}/handoff-{your-name}.md
```

```markdown
## Handoff — {agent-name}
### Role & Task
### What I Was About To Do
### Key Context
### Open Advice
### Recommended Start
```

Message team-lead about the context limit, finish your current micro-step cleanly, mark task state, then stop.

## Context Limit

If you sense your context is getting long (2+ tasks completed, many file reads), write a handoff to `.popcorn-xp/{team-name}/handoff-{your-name}.md` using the handoff format, message team-lead and your current partner about the context limit, finish your current micro-step cleanly, mark task state, then stop.

If Claude compacts your context before you stop:

1. Write or update your handoff immediately
2. Message the lead or next driver with the handoff path
3. Expect to be retired on your next idle cycle so a fresh teammate can continue with your handoff and the compact summary

After context compaction, before resuming work:

1. Check TaskList for current task status
2. Read LOG.md for latest checkpoints
3. Read ADVICE.md for any open items
4. Check git log for recent commits

Do not re-do work that's already complete.

## Rotation

After your drive task completes, commit your changes before anything else:

```bash
git add <files you changed>
git commit -m "feat(scope): what you did (task {id})"
```

Use semantic commit style: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`. Stage only the files you touched. Write a commit message that says what the task accomplished, not a file-by-file changelog. Then log the commit hash in your checkpoint.

**Paired task rotation:** When the lead assigns the next task pair, roles swap:

- The agent who navigated T1 receives the T2 drive task (becomes driver)
- The agent who drove T1 receives the T2 nav task (becomes navigator)

**Do not self-navigate.** If you drove a task, you should not navigate the review of that same work. The lead should assign a different agent as navigator. If you find yourself reviewing your own changes, flag it to the lead — it defeats the purpose of pair review.

On rotation:

- Create `.popcorn-xp/{team-name}/snapshot-{your-name}.md` with touched files, verification run, open advice, and the next risk.
- Send a handoff message to the new driver: what you changed, what's tricky, what to watch out for.
- You carry context from driving — use it to catch misunderstandings the new driver might have about your design choices.

For bugfix sessions, the lead may declare explicit lanes instead of strict alternation:

- tester drives confirmation+RED pair
- craftsman or expert drives GREEN pair
- a fresh-eye verification pair closes the loop

This is allowed when it simplifies the session, but it is not a free pass for one agent to drive everything.

For ambiguous tasks, do not start editing immediately. First:

1. Driver sends a 2-4 sentence approach note.
2. Navigator publishes READY with the main risk or test plan.
3. Driver begins implementation only after that handshake.

If the lead overrides your assignment (reassigns, reorders, or redirects), follow their direction — they see the full session and the user's intent.

## Retro

Before shutdown, the lead asks for retro feedback. When you receive a retro request, respond with **process observations**, not task status:

- What worked well about the pairing dynamic?
- What made collaboration harder?
- Did the advice system help or get in the way?
- Were checkpoints frequent enough for useful navigation?
- What would you change about the rotation or task breakdown?

Do NOT describe what you built or what bugs you found — that's in LOG.md. Focus on the collaboration process: pairing dynamic, advice quality, checkpoint frequency, rotation, communication friction.

Submit your observations using the session script:

```
.popcorn-xp/{team-name}/session retro {your-name} 'What worked? What didn't? What would you change about the process?'
```

Keep it brief (3-5 sentences). Focus on the process, not the code. "The OBJECTION on depth checking caught a real bug" is useful. "I completed task 3" is not — the lead already knows that from the TaskList.

## Integration Notes

- The lead sets up the dependency chain and session lifecycle. Teammates self-progress through the task chain based on rotation convention (navigator claims the next unblocked task). The lead intervenes on exceptions — reordering, reassignment, scope changes — not on every transition.
- If a teammate needs context the lead has, the lead sends it via SendMessage.
- If the task becomes straightforward after the first round, the lead can tell the team to finish up and avoid spawning unnecessary additional tasks.
- The lead runs final verification through a teammate, not directly (coordinator mode has no file tools).
- Before shutdown, the lead asks for retro feedback. See the Retro section above — respond with process observations, not task summaries.
- On session close, the lead signals shutdown mechanically. Submit your retro when asked — the session cannot close until you do.
