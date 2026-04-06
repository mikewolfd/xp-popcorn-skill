# Dual-Mode Runtime Proposal

Proposal to support two coordination modes in Popcorn XP:

- `team` — the current agent-teams path for live peer-to-peer pairing
- `subagent` — a lighter path that uses subagents plus durable file-based coordination

The design below is **implemented** in this repository (`bin/session`, `session-common.sh`, gated hooks, tests in `tests/test-hooks.sh`). This document remains the architectural reference for why the two modes exist and how they differ.

This proposal retains the current `team` paradigm and adds `subagent` as a separate mode. It does not replace the existing team design. It formalizes two supported ways to run the same product model.

## Executive Summary

Popcorn XP currently assumes one runtime model: agent teams with direct messaging, shared tasks, and team lifecycle hooks. That model is powerful when the platform behavior is reliable. It is also the source of most of the system's runtime complexity.

The proposal is to split the product into two explicit options:

- **`team` mode** keeps the current model for users who want true live pairing.
- **`subagent` mode** keeps the XP lenses, advice types, session files, and shutdown discipline, but replaces live peer messaging with lead-orchestrated subagents plus a durable file-backed task bus.

The important design choice is this: both modes should share the same durable coordination layer. `LOG.md`, `ADVICE.md`, agent state, READY artifacts, handoffs, snapshots, and retros are not team-only concepts. They are the stable core. The runtime mode decides how agents communicate, how they are resumed, and how much the platform enforces mechanically.

The separation matters:

- retain the current `team` path as-is for live agent-teams sessions
- add `subagent` as a separate runtime path
- keep coordination artifacts separate by purpose instead of collapsing them into one stream

## Why Two Modes

The codebase already has two competing truths:

- The product philosophy is about pairing, rotation, typed advice, and durable session memory.
- The runtime implementation is heavily shaped by agent-teams primitives such as `TeamCreate`, `TaskUpdate`, `TeamDelete`, `TeammateIdle`, and `SendMessage`.

Those are not the same thing.

The pairing model is the product. Agent teams are one transport. Subagents are another.

Two modes let Popcorn XP keep the stronger team experience without forcing every session onto the most complex runtime path.

The design is additive, not replacement-oriented.

- `team` remains a first-class mode
- `subagent` becomes a second first-class mode
- implementation should not blur the two into one half-supported hybrid

## Product Goals

Both modes should preserve the same user-facing promises:

- Agents work through explicit lenses.
- Advice has typed weight: `OBJECTION`, `SMELL`, `STEER`, `FYI`.
- `OBJECTION`s block completion until engaged.
- Session history survives context loss.
- Rotation, handoff, and retros remain first-class behaviors.

The modes differ in runtime behavior and immediacy guarantees:

- **`team`** optimizes for immediacy and live coordination.
- **`subagent`** optimizes for reliability, simplicity, and durable auditability through asynchronous coordination inside one lead-owned session.

## Working Topology

Both modes should preserve the same working topology:

- one **lead** who orchestrates but does not drive
- one **driver** who edits the current task
- one **navigator** who stays ahead of the driver, reads upcoming code, and publishes READY artifacts
- one **advisor** who reviews the current and recent work through a separate lens and sends advice

That is the default three-member working team. The product is not just "a driver and a navigator." It is a pair plus an active reviewer.

The advisor is not the same as the independent `code-reviewer` agent.

- the **advisor** is part of the live working team
- the **code-reviewer** is a periodic independent auditor the lead may launch separately

The topology should stay stable across both modes even when the transport changes.

### Advisor Model

The default advisor model should be simple:

- one **session-scoped advisor** follows the session continuously
- that advisor reviews the current task, the immediately previous work, and any risky shared files
- the advisor does not take the write lock unless explicitly reassigned into a driving role

Task-scoped specialist review is still allowed, but it should be treated as an override, not as a second ambiguous baseline.

- default: one standing advisor for the session
- override: a task may temporarily assign a specialist reviewer for that task
- the independent `code-reviewer` remains separate from both

## Proposed Modes

### Mode 1: `team`

This is the current architecture and remains supported.

Characteristics:

- Uses `TeamCreate`, `TaskUpdate`, `TeamDelete`, and `SendMessage`
- Supports direct teammate messaging
- Uses hooks for claim enforcement, idle enforcement, and lifecycle gating
- Best when the pair dynamic depends on low-latency interaction

Use `team` when:

- the user explicitly wants live pair-style collaboration
- the task benefits from direct navigator interruption
- the platform's agent-teams runtime is behaving well enough to trust

### Mode 2: `subagent`

This is a new runtime path built around durable files rather than live mailboxes.

Characteristics:

- Uses subagents, typically in background, instead of teammates
- Keeps the lead as the only orchestrator; subagents do not coordinate lifecycle directly with each other
- Replaces tactical peer-to-peer `SendMessage` traffic with a file-backed task bus
- Keeps `ADVICE.md` as the blocking critique ledger
- Keeps `LOG.md` as the execution history
- Adds task-scoped chat files for back-and-forth discussion
- Treats subagents as resumable workers, not as teammates with native idle semantics
- Uses polling, `/loop`, or explicit subagent resume as the wake-up path
- Supports subagent-local hooks only when the runtime materializes project-local agent definitions; otherwise enforcement stays in the main session plus `bin/session`

Suggested session structure:

```text
.popcorn-xp/{session}/
  LOG.md
  ADVICE.md
  RETRO.md
  agent-state/
  tasks/
    T1/
      back-forth.md
      meta.json
    T2/
      back-forth.md
      meta.json
```

Use `subagent` when:

- direct teammate messaging is unreliable
- the task is sequential enough that polling is acceptable
- the user wants simpler, more debuggable coordination
- durable history matters more than low-latency interaction
- permissions are already broad enough that background subagents will not stall on repeated prompts
- the lead can stay responsible for orchestration, wake-ups, and final closeout

### Subagent Runtime Constraints

The official subagent model is capable enough for a second pairing mode, but it is not a drop-in clone of agent teams.

Important platform facts:

- Background subagents can run concurrently
- Subagents can define `PreToolUse`, `PostToolUse`, and `Stop` hooks
- The main session can observe `SubagentStart` and `SubagentStop`
- Each subagent invocation starts fresh unless the lead resumes that subagent
- The design should not assume a subagent can remain meaningfully idle forever and then self-wake like a teammate
- Subagents cannot spawn other subagents
- Plugin-provided subagents do not get `hooks`, `mcpServers`, or `permissionMode`
- Agent teams remain the intended tool for agents that need native parallel communication

That implies a concrete design stance:

- `team` mode remains the live, peer-messaging option
- `subagent` mode should be described as asynchronous durable pair programming, not as "team mode but cheaper"
- the lead stays in charge of task assignment, wake-ups, rotation, and shutdown
- driver, navigator, and advisor remain distinct working roles even though the lead now mediates their wake-up cycle
- the file bus is the canonical coordination contract even if resume is used as a convenience optimization
- any hook-heavy `subagent` design must either generate project-local `.claude/agents/*` definitions or keep enforcement in session-global hooks and the shell layer

## Shared Core

The two modes should share one runtime core. That core already exists in rough form.

### Keep as the canonical session API

- `bin/session`
- `hooks/scripts/session-common.sh`

These files already own much of the durable coordination model:

- append-only logging
- append-only advice
- explicit agent state
- READY artifacts
- handoffs and snapshots
- retro and shutdown markers

This proposal treats `bin/session` as the primary runtime interface, not as a helper script hidden behind the team model.

### Keep as the canonical durable files

- `LOG.md` — what happened
- `ADVICE.md` — what was challenged and how it was resolved
- `agent-state/*.json` — machine-readable role and phase state
- `navigator-ready-*.md` — explicit READY artifacts
- `handoff-*.md` and `snapshot-*.md` — context transfer
- `.retro-*`, `.shutdown` — session lifecycle signals

These artifacts should exist in both modes.

## Existing Script Reuse

The shell layer is reusable if it is split correctly.

### Reuse as-is or close to as-is

#### `bin/session`

This should remain the write API for both modes. Extend it with task-bus commands instead of introducing a separate service first.

Implemented commands (non-exhaustive; see `bin/session`):

- `session task-init {task-id}`
- `session task-claim {task-id} {agent} {role} [expected-revision]` — optional numeric CAS on `meta.json` `revision` after session lock; mismatches fail with a clear error
- `session task-revision {task-id}` — print current revision for clients
- `session task-advisor-scope {task-id} true|false` — sets `advisor_session_default` in `meta.json`
- `session task-release` / `task-complete` / `task-abandon` — clear roles, bump `revision`, append to `LOG.md` where applicable
- `session close-check` / `session close` / `session close --force` — `close` runs `close-check` unless `--force`
- `session chat …` / `chat-read` / `cursor-get` / `cursor-ack`
- `session health` / `session health --strict` — lead-side diagnostics
- Append-only `events.jsonl` in the team directory for automation (task claims, chat, close, etc.)

In `subagent` mode, `task-claim` plus the session directory lock and `revision` CAS provide the atomicity that `TaskUpdate` supplied in `team` mode. Reserved `lease_holder` / `lease_epoch` fields in `meta.json` remain available for future stricter leasing if needed.

`task-claim` and `task-complete` should also be the points where role semantics stay explicit:

- driver owns the active write lock
- navigator owns read-ahead and READY publication for the paired task
- advisor owns review of recent/current work and advice publication, without taking the write lock unless explicitly reassigned

`close-check` and `close` should be the subagent-mode replacement for the cleanup guarantees that `TeamDelete` currently provides in `team` mode.

#### `hooks/scripts/session-common.sh`

This is the right place for shared runtime helpers:

- session discovery
- state-file access
- unresolved advice detection
- agent normalization
- write-set checks

It should become the shared library for both modes.

#### `hooks/scripts/check-advice-on-complete.sh`

The advice-resolution logic is still correct in both modes because it depends on `ADVICE.md`, not on team messaging.

What is not reusable as-is is the trigger. Today it runs on `TaskCompleted`. In `subagent` mode, the same check must be invoked by a new completion path such as `session task-complete`, a subagent `Stop` hook, or a lead-side closeout check.

### Reuse with edits

#### `hooks/scripts/enforce-no-idle.sh`

The state machine is useful. The `TeammateIdle` trigger and some transport assumptions are not.

Keep:

- retro pending
- shutdown pending
- compacted handoff enforcement
- explicit waiting states
- generic "declare next action" nudges

Replace:

- `context-store.log` checkpoint logic
- advisor review cursor logic tied to edit events
- messaging-specific shutdown wording
- teammate-only assumptions about who triggers the enforcement cycle

In `subagent` mode, idle enforcement should look at:

- unread task-bus entries
- stale task cursors
- missing READY artifacts
- unresolved `OBJECTION`s
- overdue advisor review passes on the current task

**Shipped:** `enforce-no-idle.sh` keeps the same retro / shutdown / compaction / advice phases as team mode, swaps context-store checks for **task chat + `session review` / `cursor-ack`** for advisors and navigators in **`waiting_on_driver`**, and skips working nudges when there is no **`agent-state`** registration (or **`role`** and **`phase`** are both empty).

Possible implementation shapes:

- subagent-local `PreToolUse` and `PostToolUse` hooks when using generated project-local agents
- subagent `Stop` hooks to force handoff/snapshot discipline
- lead-side scheduled checks or explicit resume nudges when relying on background agents without local hook packaging

#### `hooks/scripts/mark-compact-pending.sh`

#### `hooks/scripts/record-compact-summary.sh`

These are still useful if compacted agents need to hand off in either mode.

#### `hooks/scripts/context-store-log.sh`

Do not keep it as a file-edit store in `subagent` mode. Reuse the append-only log and cursor pattern for task chat.

### Team-only or likely retired in `subagent` mode

#### `hooks/scripts/check-task-claim.sh`

#### `hooks/scripts/update-task-state.sh`

These are tightly coupled to `TaskUpdate` and the team task list. In `subagent` mode, the current implementations are not reusable.

Their invariants are still required:

- only one active driver at a time
- no concurrent ownership of unrelated tasks by the same agent
- rotation should not silently collapse into the same driver forever

Those checks need to move into `session task-claim`, task metadata, or lead-side claim arbitration. They should not be dropped just because `TaskUpdate` disappears.

#### `hooks/scripts/check-retro-before-delete.sh`

#### `hooks/scripts/cleanup-context-store.sh`

These are specific to `TeamDelete` and the context store. **`subagent` mode:** both scripts **exit 0 immediately** (no RETRO gate on `TeamDelete`, no context-store cleanup) so closeout stays on **`session close-check` / `session close`** instead of team deletion.

#### `hooks/scripts/context-store-check.sh`

#### `hooks/scripts/context-store-mark-dirty.sh`

These are specific to the old soft-lock and edit-log model. They should not be reused as-is.

## Coordination Model in `subagent` Mode

`subagent` mode should use three channels, each with one purpose:

- `LOG.md` — execution history
- `ADVICE.md` — typed critique and resolutions
- `tasks/T{n}/back-forth.md` — tactical conversation for one task

Each task should also keep lightweight metadata in `tasks/T{n}/meta.json`:

- current driver
- current navigator
- assigned advisor for this task
- whether that advisor is the session default or a task-scoped override
- claim/lease state
- unread cursor positions
- task status

That keeps the architecture simple:

- important critique goes to `ADVICE.md`
- general progress goes to `LOG.md`
- tactical back-and-forth stays local to the task
- role ownership and task status stay in task metadata

This avoids overloading `ADVICE.md` with casual discussion and avoids turning `LOG.md` into a chat transcript.

### Artifact Boundaries

Keep the artifacts separate.

- `LOG.md` is for checkpoints, decisions taken, and execution history
- `ADVICE.md` is for typed critique plus typed resolutions
- `tasks/T{n}/back-forth.md` is for tactical conversation
- `tasks/T{n}/meta.json` is for machine state

Do not collapse these into one markdown file.

Likewise, do not blur runtime modes.

- `team` mode keeps native team primitives and team-oriented enforcement
- `subagent` mode keeps lead-orchestrated subagents, file-bus coordination, and resumable workers
- shared concepts should be shared deliberately through `bin/session` and the durable files, not by muddling the runtime boundaries

A machine-facing **`events.jsonl`** (per session directory) is implemented for tooling; human-facing splits (`LOG.md`, `ADVICE.md`, task chat, `meta.json`) stay separate.

`subagent` mode should also avoid reintroducing a human-facing global context log equivalent to the old `context-store.log`. If a low-level event stream is needed for automation, keep it internal and machine-oriented.

### Advice Promotion Rule

The routing rule should be strict:

- **typed advice** belongs in `ADVICE.md`
- **tactical discussion** belongs in task chat

That means:

- `OBJECTION`, `SMELL`, `STEER`, and `FYI` must be appended to `ADVICE.md`
- task chat may reference the advice ID, discuss it, or negotiate it
- task chat is never the sole source of truth for typed advice

If a comment might block completion, reopen a task, or matter after the current turn, it must be promoted to `ADVICE.md` immediately.

The file bus should be the source of truth. Resume is an optimization, not the source of truth.

That means:

- if a navigator is asleep, the lead may resume it and point it at unread task chat
- if an advisor is asleep, the lead may resume it or run a scheduled review pass; the design should not depend on the advisor "just noticing"
- if a driver stops unexpectedly, a fresh subagent can reconstruct state from the durable files
- no important coordination should exist only in ephemeral background-subagent context

### Wake-Up Hierarchy

The wake-up story should be explicit.

Preferred order:

1. **Resume the same subagent** when the runtime supports it cleanly.
2. **Use scheduled prompts** such as `/loop` for standing navigator/advisor review passes when continuous awareness matters more than exact identity continuity.
3. **Respawn a fresh subagent from durable files** when resume is unavailable, unreliable, or too expensive to reason about.

Design rule:

- resume is an optimization
- respawn from files is the hard fallback
- no correctness property should depend on resume being available

This matters because background subagents are good workers, but they are not a trustworthy substitute for teammate idle semantics.

## Typical Session Flow

The session shape should be easy to explain.

### `team` mode

1. The user gives the task to the lead.
2. The lead creates the team, the session files, and the first task pair.
3. The lead assigns a driver, a navigator, and an advisor.
4. The driver works on the current task and sends checkpoints.
5. The navigator stays ahead, reads upcoming code and constraints, publishes a READY artifact, and interrupts when needed.
6. The advisor reviews the current and recent changes through a separate lens and sends advice.
7. All three write durable state to `LOG.md`, `ADVICE.md`, and agent-state files.
8. The lead handles escalations, rotates roles, and closes the session.

Communication pattern:

- user -> lead
- lead -> driver, navigator, advisor
- driver <-> navigator
- advisor -> driver and lead
- everyone -> durable session files

### `subagent` mode

1. The user gives the task to the lead.
2. The lead creates the session files, task metadata, and the first working trio: driver, navigator, advisor.
3. The lead spawns or resumes the relevant subagents.
4. The driver claims the active write task and records progress in `LOG.md` and task chat.
5. The navigator reads ahead, publishes READY, and writes typed advice to `ADVICE.md` plus tactical notes to the task bus.
6. The advisor reviews the current and recent work, then writes typed advice to `ADVICE.md` and discussion to the task bus when needed.
7. When the navigator or advisor needs another turn, the lead wakes them by resume or by scheduled checks such as `/loop`.
8. The lead rotates roles, resolves blocked states, and closes the session using the durable files as the source of truth.

Communication pattern:

- user -> lead
- lead -> driver, navigator, advisor
- driver -> task bus and durable files
- navigator -> task bus, READY artifacts, and advice ledger
- advisor -> task bus, execution log, and advice ledger
- lead -> subagent resume or scheduled wake-ups

The point of the `subagent` design is not to fake native teammate messaging. The point is to preserve the same collaborative roles while moving coordination onto durable, inspectable artifacts.

## Subagent Closeout Contract

`subagent` mode needs an explicit close sequence because there is no `TeamDelete` event to lean on.

Suggested contract:

1. The lead calls `session retro-request`.
2. Every active worker either:
   - submits a retro, or
   - is marked retired with a handoff already captured.
3. Every active task claim is released or explicitly marked abandoned.
4. `session close-check` verifies:
   - no unresolved `OBJECTION`s
   - no active write lock
   - required handoffs exist for retired workers
   - required retros exist for active participants
5. The lead appends this session’s summary to **`RETRO.md`** (accumulated across sessions; same minimum substance as team-mode `TeamDelete` retro: at least **5 lines** of real content).
6. The lead calls **`session close`**, which re-runs `close-check` then requires **`RETRO.md`** to exist with **≥5 lines** in `subagent` mode, then writes **`.closed.json`**. **`session close --force`** skips both `close-check` and the `RETRO.md` gate (escape hatch only).

`subagent` mode should not delete its coordination artifacts at close. The default should be to keep the session directory as an auditable record and a recovery point.

## Implementation Guardrails

The proposal is only worth shipping if these guardrails hold:

- `session task-claim` must be atomic enough to enforce one active driver at a time
- every important state transition must survive worker loss in durable files
- every role must be recoverable by respawning from `LOG.md`, `ADVICE.md`, task chat, and task metadata
- typed advice must remain mechanically queryable
- closeout must be verifiable by **`session close-check`** plus **`session close`** (including `RETRO.md` in `subagent` mode), not by lead intuition alone

Non-goals:

- perfect emulation of native teammate messaging
- preserving every agent identity forever
- building MCP infrastructure before the file-backed design proves insufficient

Success for `subagent` mode means keeping the collaboration outcome while accepting a more explicit, more recoverable, and slightly less magical runtime.

## Why Not Start with MCP

An MCP-based chat bus is a valid future option. It is not the right first move.

MCP is justified only if the file bus proves insufficient in one of these ways:

- polling latency is too slow
- agents need delivery acknowledgements
- routing needs to be richer than task-scoped append-only chat
- external tooling or UI integration becomes necessary

None of those needs are proven yet.

The file bus has strong advantages:

- durable by default
- easy to inspect and debug
- no external process
- no extra deployment or operational surface
- can be implemented by extending `bin/session`

If a richer bus is needed later, the file-bus API can become the contract the MCP server implements.

## User Experience

The user should choose a mode explicitly, or Popcorn XP should choose conservatively.

Suggested interface:

- `popcorn this task using team mode`
- `popcorn this task using subagent mode`

Suggested default:

- **Operationally, default to `subagent` for new Claude Code sessions** until native **team** mode stops exhibiting runaway token use from current platform behavior (treat **team** as explicit opt-in with that risk understood).
- Prefer `subagent` when the task can tolerate asynchronous coordination, permissions are already broad enough, and no mid-flight user clarification is likely.
- Switch to `team` only when the user explicitly wants live pairing and accepts the current token-cost risk, or when the task truly benefits from direct low-latency coordination enough to justify it.

That default is pragmatic. Reliability is the safer baseline than cleverness.

## Migration Shape

This proposal does not require a big-bang rewrite.

### Phase 1: Name the modes

- Document `team` as the current path
- Add `subagent` as a proposed path
- Keep behavior unchanged

### Phase 2: Promote the shared core

- Extend `bin/session`
- centralize helpers in `session-common.sh`
- define task-bus file formats
- define claim/lease semantics for `subagent` mode so rotation and single-driver rules remain mechanical

### Phase 3: Build `subagent` mode

- add task chat files
- replace tactical `SendMessage` assumptions in the protocol
- adapt idle enforcement to task chat and explicit cursors
- choose the hook packaging strategy:
  either generate project-local `.claude/agents/*` definitions with hooks, or keep enforcement in the main session plus shell scripts
- use subagent resume as a wake-up optimization, not as the only coordination channel

### Phase 4: Simplify hooks

- keep hard gates shared by both modes
- limit team-only hooks to the `team` path
- remove context-store hooks from the `subagent` path

## Recommendation

Adopt a dual-mode product:

- **Keep `team` mode** for users who want real live pairing and are willing to accept the heavier runtime.
- **Build `subagent` mode** as the default path for compatible tasks: asynchronous pairing, durable coordination, and lead-owned orchestration.

Do not create a `task-chat-mcp` first.

First, extend `bin/session` into a durable task-bus API, preserve the existing invariants with explicit claim semantics, and pick a concrete subagent-hook packaging strategy. Once the file-backed design is proven in practice, decide whether an MCP transport adds enough value to justify the extra system.

## Implementation status (this repo)

| Area | Shipped behavior |
|------|------------------|
| Mode switch | `.runtime-mode` + `session mode team` or `subagent`; **if the file is missing, mode is `subagent`** (write `team` to opt into Agent Teams) |
| Task bus | `tasks/T{n}/meta.json`, `back-forth.md`, revision + `advisor_session_default`, per-agent chat cursors |
| Claims | `task-claim` with session lock, single-driver rules, rotation, optional expected-revision CAS |
| Closeout | `close-check` + `session close` → `.closed.json`; **`subagent`:** `close` also requires `RETRO.md` (≥5 lines); **`close --force`** skips `close-check` and `RETRO.md`; session dir retained |
| Hooks | Team-only scripts no-op in subagent; `enforce-no-idle` uses task chat / cursors for advisors and navigators in `waiting_on_driver`; `SubagentStop` runs OBJECTION + warnings + compaction-pending hint |
| Audit | `events.jsonl` via `px_event_log` (set **`POPCORN_XP_EVENT_LOG_DEBUG`** to surface append/`jq` failures on stderr) |
| Tests | Dual-mode cases prefixed `DM-` in `./tests/test-hooks.sh` |

**Not in scope here:** generated per-project subagent definitions with bundled hooks, MCP bus, or Codex-specific runtime guarantees (see `docs/dual-mode-codex-companion.md`).
