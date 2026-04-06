# Popcorn XP

> [!WARNING]
> **Claude Code — native `team` mode (Agent Teams + `SendMessage`):** This transport can burn through **very large token budgets** because of a **bug in Claude Code**, not in Popcorn XP. **Avoid `team` mode for day-to-day work** until Anthropic fixes it. Use **`subagent`** mode instead: leave **`.runtime-mode`** unset or set it to **`subagent`** (file bus via **`bin/session`**). Only opt into **`team`** if you explicitly need live peer messaging and accept the cost.

XP pair programming for Claude Code agents: **one driver, one navigator, one advisor** — **current, future, and past** respectively. The driver implements what is happening now; the navigator reads ahead and steers; the advisor reviews what already landed (verification, regressions, objections). Roles rotate between tasks; **OBJECTION** blocks task completion until the driver engages.

> **Default path:** **`subagent`** — lead orchestrates workers; coordination through **`bin/session`**, `tasks/T{n}/`, and **`ADVICE.md`**. **`team`** exists for parity and power users who opt in after reading the warning above.
>
> **OpenAI Codex:** subagent-shaped integration only — [`.codex/`](./.codex/), [`codex/`](./codex/), [docs/dual-mode-codex-companion.md](./docs/dual-mode-codex-companion.md). No Codex-native `team` transport.

## What it does

Say *“popcorn this task”* (or *pair program*, *XP session*, *team of agents*). The lead skill sets up `.popcorn-xp/{team}/`, tasks, and teammates. **Subagent (default):** the lead keeps normal file tools and spawns subagents; peers sync via the **file task bus**, not peer `SendMessage`. **Team mode:** the lead runs **coordinator-only** (no Read/Write/Edit/Bash) and teammates use **Agent Teams** messaging. Pairing, rotation, and advice rules are the same; diagrams below describe **team** transport — on the subagent path, read **`SendMessage`** as **task chat + session files**.

**Pairing:** one **writer** at a time (the driver — **present** work). The navigator holds the **future** line of sight (files and checkpoints not yet reached, approach risks). The advisor holds the **past** line of sight (what merged, what tests prove, what should have been caught). **Rotation:** driver and navigator swap across tasks so context moves with the pair; the advisor stays the standing reviewer unless you rotate that seat by design. **Soft locks (team mode):** hooks warn when another agent is editing a file you read. Durable history lives in **LOG.md** and **ADVICE.md**; team chat is ephemeral and capped.

Full teammate rules and templates: [references/protocol.md](./references/protocol.md). Lead procedure: [skills/popcorn-xp/SKILL.md](./skills/popcorn-xp/SKILL.md).

### Team mode shape (reference)

```
You
 │
 ▼
Lead (Coordinator Mode)
 │  TeamCreate, TaskCreate, Agent, SendMessage, TaskStop — no filesystem tools
 │
 ├──► driver ◄──── SendMessage ────► navigator
 │    current: implements now         future: reads ahead, steers
 │
 └──► advisor — past: reviews what landed, tests, OBJECTIONs
```

### Typed advice

| Type       | Meaning                         | Blocks? |
|------------|----------------------------------|--------|
| **OBJECTION** | “This is wrong” — must engage | Yes    |
| **SMELL**  | “Looks off”                      | No     |
| **STEER**  | “Consider another approach”      | No     |
| **FYI**    | Context                          | No     |

Advice is appended to **ADVICE.md**. In **team** mode it is also sent via **SendMessage**. Hooks enforce **OBJECTION** resolution on task completion (and on **SubagentStop** in subagent mode). Open SMELL/STEER/FYI items are surfaced as reminders, not hard blocks.

### Session files & mode

```
.popcorn-xp/{team}/
├── LOG.md          # Checkpoints / narrative
├── ADVICE.md       # Typed advice + resolutions
├── RETRO.md        # Retros (accumulated)
├── .runtime-mode   # omit ⇒ subagent; or: team | subagent
├── tasks/T{n}/     # Subagent task bus (meta, back-forth, …)
└── session         # exec wrapper → bin/session
```

**`session mode subagent|team`** writes **`.runtime-mode`**. Design notes: [docs/dual-mode-proposal.md](./docs/dual-mode-proposal.md).

**LOG.md** is append-only: task header, numbered checkpoints (“what changed, files, next step”), then a **Task Complete** line. **ADVICE.md** mirrors typed advice with stable IDs; resolutions append **OUTCOME** lines (**FIXED**, **REJECTED**, **INCORPORATED**, **NOTED**) so hooks can tell what is still open. Example shape:

```markdown
## Task 2 — Driver @craftsman, Navigator @expert
### Checkpoint 1
Guarded parse depth; tests still green.
### Task Complete
Ready for verification.
```

```markdown
### OBJECTION OBJ-2-01 — open
depth < 0 unhandled in parseBlock (src/parser.ts:47)
### OBJ-2-01 — OUTCOME FIXED
Added guard + regression tests in checkpoint 2.
```

### Task ownership (team mode)

There is no **LOCK.md**. The platform **TaskList** tracks who owns **`in_progress`** work; the lead uses **TaskUpdate**, teammates self-claim from the queue, and hooks guard bad claims. **Subagent** mode uses **`session task-claim`** / **`task-release`** instead — see protocol.

## Why not hub-and-spoke?

Classic multi-agent setups centralize thinking in one orchestrator. Popcorn XP pushes **peer coordination**: navigator and driver talk **during** the work (team: `SendMessage`; subagent: task chat + files), not only through a lead recap. **Team** mode enforces that structurally by stripping file tools from the coordinator lead. **Subagent** mode keeps the same invariants via files and hooks while the lead stays a normal coding agent.

## Hooks (high level)

Registered in **`hooks/hooks.json`**. All are **no-ops** when there is no active session (no **`.popcorn-xp/.active-team`**). In **`subagent`** mode, team-only scripts (**context-store**, **TaskUpdate** sync, **TeamDelete** cleanup) **no-op**; **TeammateIdle** still handles retro/shutdown/compaction and subagent-specific cursors; **SubagentStop** runs the advice check.

| Event / tool hook | Script | Role |
|-------------------|--------|------|
| TaskCompleted | `check-advice-on-complete.sh` | Block on open OBJECTIONs; warn on other open advice |
| SubagentStop | `check-advice-on-subagent-stop.sh` | Subagent-mode OBJECTION gate + warnings |
| TeammateIdle | `enforce-no-idle.sh` | Idle nudges, checkpoints, shutdown lifecycle |
| Pre/Post Compact | `mark-compact-pending.sh`, `record-compact-summary.sh` | Compaction handoff markers |
| PreToolUse Read / Edit | `context-store-*.sh` | Soft lock awareness (**team**) |
| PreToolUse TaskUpdate | `check-task-claim.sh` | Claim / rotation guards (**team**) |
| PostToolUse TaskUpdate | `update-task-state.sh` | Mirror task state to **`agent-state/*.json`** (**team**) |
| Pre/Post TeamDelete | `check-retro-before-delete.sh`, `cleanup-context-store.sh` | Retro gate + cleanup (**team**) |

Append-only **`.popcorn-xp/context-store.log`** backs the soft-lock story. Each **EDIT** records agent, path, and time; the latest **EDIT** per path defines who last touched the file. **PreToolUse(Read)** warns when you read a file last edited by someone else (cross-agent only). **PreToolUse(Edit/Write)** marks dirty and warns if another agent was already editing — awareness, not a hard merge lock.

**Shutdown / retro (idle hook):** phases include retro pending, shutdown approval, compaction handoffs, and normal working nudges. Subagent mode keeps these gates but swaps context-store checkpoint math for **task chat** and **cursor-ack** rules for navigators and advisors. Precise state machine: **CLAUDE.md** and **protocol**.

Maintainer detail: **[CLAUDE.md](./CLAUDE.md)**.

## Paired tasks

Logical work is split into **paired** tasks: a **drive** task plus a matching **navigate** task so pairing is visible in the task list. Navigators stay responsible through the driver’s cycle and finish after verifying the driver’s output. Rotation is encoded in assignments (e.g. T1’s navigator claims T2’s drive task). The lead skill spells out the pairing pattern step by step.

## Setup

**Claude Code** v2.1.32+, **Opus** where Agent Teams are used.

**For native `team` mode**, set in `~/.claude/settings.json` and restart:

```json
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1",
    "CLAUDE_CODE_COORDINATOR_MODE": "1"
  }
}
```

**Subagent-default** sessions do not require the lead to be coordinator-only; teammates still use hooks and **`bin/session`**.

Install the skill:

```bash
npx skills add https://github.com/mikewolfd/xp-popcorn-skill --skill popcorn-xp
npx skills add /path/to/popcorn-xp --skill popcorn-xp   # local checkout
```

If you only install **`popcorn-xp`** (lead), also load **`popcorn-xp-protocol`** for teammates that are not defined in this plugin’s **`agents/`** frontmatter — native agents from other plugins should invoke that skill first per protocol docs.

**Visibility:** `tmux` (or iTerm2 with `it2`) gives split panes per teammate; otherwise teammates often run in-process/background.

### `bin/session` (subagent highlights)

Common subcommands (see **`bin/session` help** and **dual-mode doc** for the full set): **`log`**, **`advice`**, **`resolve`**, **`state`**, **`ready`**, **`task-init`**, **`task-claim`**, **`task-revision`**, **`task-release`**, **`task-complete`**, **`task-abandon`**, **`chat`** / **`chat-read`**, **`cursor-get`** / **`cursor-ack`**, **`review`** (advisor cursor), **`health`**, **`close-check`**, **`close`** / **`close --force`**, **`mode`**. Optional audit stream: **`events.jsonl`** when **`POPCORN_XP_EVENT_LOG_DEBUG`** is set (see **CLAUDE.md**).

## Workflow (sketch)

1. **Lead** — Parse the goal, pick a team name, create **`.popcorn-xp/{team}/`**, **LOG.md**, **ADVICE.md**, set **`.runtime-mode`** if not relying on default **subagent**, create tasks, spawn **three** teammates (**driver, navigator, advisor** — current / future / past). Add bench specialists when needed. Exact tool names differ by mode (**TeamCreate** / **Agent** / subagent spawns — **SKILL.md**).
2. **Driver (current)** — Owns the in-flight implementation: edit, run verification from the brief, checkpoint (LOG + peer channel); do not complete while an **OBJECTION** is unresolved.
3. **Navigator (future)** — Stays ahead of the driver: checkpoints, files not yet touched, risks and STEER/SMELL/FYI; reserve **OBJECTION** for correctness gaps; dual-write to **ADVICE.md** per protocol.
4. **Advisor (past)** — Reviews what already shipped in this task stream: logs, diffs, tests, coverage gaps; owns verification tasks when assigned; **OBJECTION** when evidence says the work is not done.
5. **Rotation** — After a task, swap driver/navigator per convention so the person who watched the code drives the next slice when possible.
6. **Closeout** — **Team:** retro rules + **TeamDelete** when satisfied. **Subagent:** **`session close-check`** then **`session close`** (and **RETRO.md** length gate unless **`--force`**) — see protocol.

Teammates may spawn focused **`claude --bare -p`** micro-runs for narrow checks without bloating the main context; optional, not the primary bus.

## Agent roster (lens ≠ job title)

The **three seats** are **driver / navigator / advisor** (current / future / past). Below are **personas** you map onto those seats — any agent file can fill any seat after rotation.

| Agent            | Default lens |
|------------------|--------------|
| scout            | Scope, constraints, risks |
| craftsman        | Implementation clarity, boundaries |
| expert           | Correctness, edge cases |
| tester           | Verification, regressions |
| strategist       | Sequencing, positioning |
| service-designer | APIs, boundaries, UX/API seams |
| visual-designer  | UI, a11y, visual patterns |
| qa               | Acceptance, E2E flows |
| product-manager  | Requirements, scope, tradeoffs |

More definitions under **`agents/`**. Lenses shape attention; **any** agent can drive or navigate after rotation.

## Tests

```bash
./tests/test-hooks.sh
```

Bash 4+, no extra deps. The suite checks:

- **Exit semantics** — `0` allows (optional JSON **additionalContext** on stdout), `2` blocks (stderr to user), other codes non-fatal.
- **Advice gate** — open **OBJECTION** IDs without matching resolutions block **TaskCompleted** (and **SubagentStop** in subagent mode).
- **Idle / rotation** — **enforce-no-idle** phases, checkpoint expectations, driver/navigator state, shutdown and retro signals.
- **Context store** — cross-agent read warnings and edit marking (**team** path).
- **Task claims** — **TaskUpdate** hooks vs **agent-state** JSON (**team** path).
- **Dual mode (`DM-`)** — subagent bypass of team-only hooks, **bin/session** task-bus commands, leases/revisions where covered.
- **Codex (`CX-`)** — shim scripts resolve repo paths correctly when **CLAUDE_PROJECT_DIR** is a temp dir.

Failing tests print **`FAIL:`** lines with expected vs actual exit codes or missing substrings.

## Repository layout

```
popcorn-xp/
├── skills/popcorn-xp/           # Lead playbook
├── skills/popcorn-xp-protocol/  # Teammate protocol (skills field)
├── agents/                      # Teammate definitions (.md)
├── bin/session                  # LOG, ADVICE, state, task bus
├── hooks/hooks.json + scripts/  # Lifecycle + tool hooks
├── references/protocol.md       # Templates & protocol detail
├── docs/                        # dual-mode proposal, Codex companion
├── .codex/ + codex/             # Codex plugin pack
├── tests/test-hooks.sh
├── plugin.json                  # Registers agents, skills, hooks
├── CLAUDE.md
└── README.md
```

`plugin.json` wires **agents/**, **skills/**, and **hooks/hooks.json** for Claude Code plugin install paths (this tree is the plugin root when used as a marketplace plugin, not only the skill tarball).

## Limitations

- **Experimental** — Agent Teams may change or be removed.
- **Claude-first** — `npx skills` is packaging; primary workflow is Claude Code (Codex: companion doc).
- **Tokens** — Several full contexts; **team** mode is especially risky for cost until the platform bug is fixed.
- **Isolation** — Teammates do not share one model context; important facts must be written or sent explicitly.
- **Message cap** — Team **SendMessage** history is capped; **LOG.md** / **ADVICE.md** are the long-lived record.
- **Coordinator / Opus** — Required for **team**-style coordinator lead and Agent Teams as documented by Anthropic.
- **Skill vs plugin** — Some users install only the **popcorn-xp** skill tarball; this repo is the **full plugin** (hooks + agents). For complete behavior, use the plugin layout or ensure hooks from this repo are active in the project.
- **Gitignored runtime** — `.popcorn-xp/` under your project is created per session and should stay out of version control (see `.gitignore` patterns in this repo).

## Credits

Built on Claude Code **Agent Teams** and **Coordinator Mode**. Inspired by Extreme Programming pair practices.

### Troubleshooting (quick)

| Symptom | Things to check |
|---------|------------------|
| Hooks never fire | **`.popcorn-xp/.active-team`** must name an existing team dir; plugin **hooks** must be enabled for the project. |
| Context-store warnings missing | You may be in **subagent** mode — those hooks intentionally no-op. |
| Task completion always blocked | Open **OBJECTION** in **ADVICE.md** without **OUTCOME**; resolve or reject with reasoning. |
| “Wrong” default mode | Missing **`.runtime-mode`** ⇒ **subagent**. Create **`team`** explicitly for Agent Teams. |
| Codex path unclear | Start with **`docs/dual-mode-codex-companion.md`** and **`codex/README.md`**. |
| Lead keeps editing files in “team” session | Coordinator mode not active — verify **`CLAUDE_CODE_COORDINATOR_MODE=1`** and restart. |
| Subagent teammate idle forever | Register **`session state`**, advance **cursor-ack** / **`session review`** per protocol; check **`.shutdown`** / retro files. |

---

### Where to read more

| Topic | Location |
|-------|----------|
| Lead runbook (spawn, tasks, shutdown) | `skills/popcorn-xp/SKILL.md` |
| Teammate rules, advice format, subagent bus | `skills/popcorn-xp-protocol/SKILL.md` |
| Long-form spawn text + mode notes | `references/protocol.md` |
| Dual mode, CAS, events, close semantics | `docs/dual-mode-proposal.md` |
| Codex hooks + layered skills | `docs/dual-mode-codex-companion.md`, `codex/README.md` |
| Hook inventory + context store | `CLAUDE.md` |
