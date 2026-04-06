## Subagent mode

The sections above define shared rules, advice lifecycle, and session file shapes. **This section is only the file-bus transport** — task claims, chat, closeout, and subagent-specific commands.

When `.popcorn-xp/{team}/.runtime-mode` is **missing** or contains **`subagent`**:

- **Claims:** Use `session task-claim {task-id} {your-short-name} driver|navigator|advisor` for locks. Release with `session task-release`. Complete with `session task-complete` (runs the OBJECTION gate).
- **Tactical chat:** `session chat {task-id} {from} {kind} "..."` — this is your **tactical peer channel** for discussion and negotiation. Typed **OBJECTION** / **SMELL** / **STEER** / **FYI** still go to **ADVICE.md** via **`session advice`** — chat is not the ledger.
- **Wake-ups:** The lead resumes you or nudges the next turn. Reconstruct state from LOG.md, ADVICE.md, task chat, and `tasks/T{n}/meta.json` if you start fresh.
- **Stopping:** `SubagentStop` enforces unresolved OBJECTIONs (same as task completion), may surface open SMELL/STEER/FYI via `additionalContext`, and nudges if `.compact-pending-{agent}.json` exists.
- **Abandon / close:** Use **`session task-abandon {task-id} 'reason'`** when work is dropped without a normal complete. **`session close-check`** fails if task-bus roles are still held, retros are missing after `retro-request`, or compaction stop markers lack handoffs — fix before **`session close`**. **`session close`** also requires **`RETRO.md`** with **≥5 lines** (append the session summary first); **`session close --force`** skips **`close-check`** and the **`RETRO.md`** gate. Successful **`close`** clears **`.popcorn-xp/.active-team`** (when it still points at this team) and truncates **`context-store.log`**; set a new active team before the next slice.
- **Task header:** Use **`session task {id}`** for a placeholder line in **`LOG.md`**; driver/navigator names are synced from **`task-claim`** / **`task-release`** so rotation is not tripped before a claim.
- **Idle (`TeammateIdle`):** Retro, shutdown, and compaction handoff rules still apply. In subagent mode, advisors are nudged when **task chat** grows past their last `session review` cursor. With no `agent-state/{you}.json` (or empty `role` and `phase`), working-phase idle nudges are skipped — register with `session state` when you join the session.

### Subagent command reference

**Task bus:**

```bash
.popcorn-xp/{team}/session task-init {n}
.popcorn-xp/{team}/session task {n}
.popcorn-xp/{team}/session task-claim {n} {your-short-name} driver|navigator|advisor [expected-revision]
.popcorn-xp/{team}/session task-revision {n}
.popcorn-xp/{team}/session task-release {n} {your-short-name}
.popcorn-xp/{team}/session task-complete {n} {your-short-name} {outcome} "note"
.popcorn-xp/{team}/session task-abandon {n} "reason"
.popcorn-xp/{team}/session task-advisor-scope {n} true|false
```

**Tactical chat (driver ↔ navigator ↔ advisor):**

```bash
.popcorn-xp/{team}/session chat {n} {from} {kind} "message"
.popcorn-xp/{team}/session chat-read {n} [start-line]
.popcorn-xp/{team}/session cursor-get {your-short-name} {n}
.popcorn-xp/{team}/session cursor-ack {your-short-name} {n} {line}
```

**Closeout:**

```bash
.popcorn-xp/{team}/session close-check
.popcorn-xp/{team}/session close
.popcorn-xp/{team}/session close --force
```

**Shared with all transports:** Use **`session advice`**, **`session resolve`**, **`session log`**, and the ADVICE.md / LOG.md rules in **Advice Lifecycle** and **Session Files** above.

If the lead assigned a write set, record it before editing:

```bash
.popcorn-xp/{team-name}/session writeset {your-name} {task-id} path/to/file1 path/to/file2
```

Before edits begin, navigators publish a READY artifact (see core rules **12** and **Rotation**):

```bash
.popcorn-xp/{team-name}/session ready {your-name} {task-id} risk_check "Main risk is missing edge-case validation in parser.ts."
```

For bugfix and RED-test tasks, run one preflight before publishing READY or writing tests:

1. Run `git log --oneline -5`
2. Read the affected files and confirm the bug still exists in current code
3. If the task description has drifted, notify the lead on **task chat** before writing tests

Record preflight conclusions in the READY line or the next **task chat** update.

When you rotate out after completing a task, create a structured snapshot:

```bash
.popcorn-xp/{team-name}/session snapshot {your-name} {task-id}
```

READ **LOG.md** and **ADVICE.md** before starting work and before completing a task.

**Retro (subagent):**

```bash
.popcorn-xp/{team-name}/session retro {your-name} 'What worked? What did not? What would you change about the process?'
```
