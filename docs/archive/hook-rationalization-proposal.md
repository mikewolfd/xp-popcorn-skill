# Hook Rationalization Proposal

Proposal to simplify the Popcorn XP hook layer without weakening the core collaboration model.

This is not a rewrite of the protocol. It is a proposal to reduce hook sprawl, remove dead or misleading runtime paths, and keep only the hook behavior that materially improves coordination.

## Executive Summary

The current system mixes four different coordination channels:

- `SendMessage` is the live collaboration bus.
- `ADVICE.md` is the persistent typed advice bus.
- `LOG.md` is the persistent progress bus.
- `agent-state/*.json` is the machine-readable runtime state for hooks.

That model is coherent. The hook layer is where it drifts.

Some hooks enforce real invariants at the right control point. Those should stay. Some hooks are dead, redundant, or mostly inject context noise. Those should be removed or merged.

The guiding rule for this proposal is simple:

- Keep hooks that enforce a hard invariant.
- Keep hooks that persist machine-usable lifecycle state another live path consumes.
- Keep hooks that inject high-signal context with better-than-prompt precision.
- Remove hooks that mostly narrate, duplicate another control point, or preserve a fantasy runtime.

## Design Context

### Communication Model

The protocol already defines the intended communication split:

- `SendMessage` is the primary realtime collaboration mechanism.
- `ADVICE.md` is the primary persistent ledger for typed critique and resolution.
- `LOG.md` is the persistent checkpoint history.
- `agent-state/*.json` is the explicit coordination state for hooks.

This matters because the hook layer should support that model, not compete with it.

### Advice Is Important, But Not The Only Bus

`ADVICE.md` is the primary persistent bus for objections, smells, steers, and resolutions. It is the correct place for hooks to look when they need to answer questions like:

- Are there unresolved `OBJECTION`s?
- Has a typed concern been engaged or ignored?

But `ADVICE.md` is not the whole collaboration model. It does not replace:

- live teammate communication via `SendMessage`
- progress tracking in `LOG.md`
- machine-readable phase and task state in `agent-state/*.json`

That distinction matters when deciding what should block idle and what should remain advisory.

### Context Store Scope

The context store is most defensible when it answers one question:

> Who is actively touching this file right now?

That supports:

- soft lock awareness
- write-set enforcement
- checkpoint accounting via edit events

The current read-side context store goes further and tries to narrate who last read a file and whether it is now "clean." That is a weaker semantic model and a much less valuable use of hook budget.

## Current Hook Surface

Active hook entrypoints in [hooks.json](/Users/mikewolfd/Work/popcorn-xp/hooks/hooks.json):

- `TaskCompleted`
  - `check-advice-on-complete.sh`
  - `check-rotation.sh`
- `SubagentStop`
  - `check-objections.sh`
- `TeammateIdle`
  - `remind-unread-advice.sh`
  - `remind-checkpoint.sh`
  - `enforce-no-idle.sh`
- `PreCompact`
  - `mark-compact-pending.sh`
- `PostCompact`
  - `record-compact-summary.sh`
- `PreToolUse TeamDelete`
  - `check-retro-before-delete.sh`
- `PreToolUse Read`
  - `context-store-check.sh`
- `PreToolUse Edit|Write`
  - `context-store-mark-dirty.sh`
- `PreToolUse TaskUpdate`
  - `check-task-claim.sh`
- `PostToolUse TeamDelete`
  - `cleanup-context-store.sh`
- `PostToolUse Read`
  - `context-store-update-read.sh`
- `PostToolUse TaskUpdate`
  - `update-task-registry.sh`

Helper scripts:

- `session-common.sh`
- `context-store-log.sh`

Orphaned scripts not wired into runtime:

- `notify-retro-written.sh`
- `notify-retro-received.sh`

## Proposal

### 1. Delete Dead Scripts

Delete:

- [notify-retro-written.sh](/Users/mikewolfd/Work/popcorn-xp/hooks/scripts/notify-retro-written.sh)
- [notify-retro-received.sh](/Users/mikewolfd/Work/popcorn-xp/hooks/scripts/notify-retro-received.sh)

#### Why

These scripts are not referenced by [hooks.json](/Users/mikewolfd/Work/popcorn-xp/hooks/hooks.json), not sourced by other hook scripts, and are already documented in backlog/history as dead runtime paths.

Keeping them implies behavior that does not exist. Dead hook code is worse than ordinary dead code because it suggests runtime enforcement that teammates and maintainers may rely on mentally.

### 2. Keep the Hard Completion Gate

Keep:

- [check-advice-on-complete.sh](/Users/mikewolfd/Work/popcorn-xp/hooks/scripts/check-advice-on-complete.sh)

#### Why

This hook enforces the single most important typed-advice invariant:

- unresolved `OBJECTION`s block task completion
- unresolved `SMELL`/`STEER`/`FYI` items remain advisory

That matches the intended "advice with teeth" model. The control point is correct because the question it answers is inherently about completion readiness.

### 3. Remove the Rotation Hook

Remove:

- [check-rotation.sh](/Users/mikewolfd/Work/popcorn-xp/hooks/scripts/check-rotation.sh)

#### Why

This hook does not enforce rotation. It only emits a warning after a task is already completed.

Problems:

- It runs too late to prevent the problem.
- It nudges the completing teammate instead of the lead.
- It falls back to scanning `~/.claude/tasks` if `team_name` is absent.
- The active tests do not meaningfully verify the task-file behavior; they only check structural properties.

Rotation is a lead policy and, if made mechanical, belongs at task assignment or claim time. A post-completion warning is low-value runtime chatter.

### 4. Remove the Backup SubagentStop Objection Hook

Remove:

- [check-objections.sh](/Users/mikewolfd/Work/popcorn-xp/hooks/scripts/check-objections.sh)

#### Why

This is redundant with two stronger control points:

- [check-advice-on-complete.sh](/Users/mikewolfd/Work/popcorn-xp/hooks/scripts/check-advice-on-complete.sh) for normal task completion
- [enforce-no-idle.sh](/Users/mikewolfd/Work/popcorn-xp/hooks/scripts/enforce-no-idle.sh) during shutdown

The backlog already notes that `SubagentStop` was not the reliable path for team-member enforcement. That makes this hook both redundant and operationally suspect.

### 5. Keep No-Idle, But Collapse It Into One Hook

Keep the no-idle policy.

Merge into one script:

- keep [enforce-no-idle.sh](/Users/mikewolfd/Work/popcorn-xp/hooks/scripts/enforce-no-idle.sh)
- fold in the logic from:
  - [remind-unread-advice.sh](/Users/mikewolfd/Work/popcorn-xp/hooks/scripts/remind-unread-advice.sh)
  - [remind-checkpoint.sh](/Users/mikewolfd/Work/popcorn-xp/hooks/scripts/remind-checkpoint.sh)

#### Why

The collaboration goal is correct: agents should not disappear silently. Idle should be blocked unless they have left useful state for teammates.

The current problem is fragmentation. Three different `TeammateIdle` hooks all block for different reasons:

- unresolved advice
- edits since last checkpoint
- missing phase / READY / handoff state

That is one policy split across three processes. It increases complexity, creates ordering ambiguity, and makes shutdown behavior harder to reason about.

#### Proposed Single Idle Policy

One `TeammateIdle` hook should block idle when any of the following are true:

- the driver has edits since the last checkpoint
- the navigator lacks a READY artifact or explicit waiting state
- a compacted agent lacks a handoff
- the agent has no declared phase / next action
- unresolved typed advice exists and the agent is trying to disappear from the collaboration loop

This preserves the "no idle agents" rule while reducing hook surface and conflict potential.

#### Advice-Specific Guidance

If advice is treated as part of the collaboration bus, then unresolved advice can legitimately block idle. But that logic should live inside the main idle state machine, not in a separate sibling hook.

### 6. Narrow the Context Store to Edit Awareness

Keep:

- [context-store-mark-dirty.sh](/Users/mikewolfd/Work/popcorn-xp/hooks/scripts/context-store-mark-dirty.sh)
- [context-store-log.sh](/Users/mikewolfd/Work/popcorn-xp/hooks/scripts/context-store-log.sh)

Remove or heavily narrow:

- [context-store-check.sh](/Users/mikewolfd/Work/popcorn-xp/hooks/scripts/context-store-check.sh)
- [context-store-update-read.sh](/Users/mikewolfd/Work/popcorn-xp/hooks/scripts/context-store-update-read.sh)

#### Why

The edit side earns its keep. It does real work:

- write-set enforcement
- soft-lock awareness
- checkpoint counting via `context-store.log` and `.checkpoint-cursor`

The read side is weaker:

- it injects context even for clean reads
- it clears `dirty` on any read
- "clean" therefore means only that someone read the file, not that all relevant agents are current

That is not a strong enough semantic model to justify persistent read-hook chatter.

#### Preferred Outcome

Option A:

- delete the read-side hooks entirely
- use the context store only for edit coordination and checkpoint accounting

Option B:

- keep a very small `context-store-check.sh`
- only emit context when a file is currently dirty and another agent is editing it
- do not narrate clean reads

Either option is better than the current read-history model.

### 7. Keep the Task Claim Guard

Keep:

- [check-task-claim.sh](/Users/mikewolfd/Work/popcorn-xp/hooks/scripts/check-task-claim.sh)

#### Why

This hook enforces real invariants at the correct point:

- no task claims after shutdown
- no claiming a new task while already driving another active task

This is exactly the kind of logic hooks are good at: crisp, mechanical, stateful, and easy to defend.

### 8. Keep the Task State Updater, But Rename It

Keep, but rename:

- [update-task-registry.sh](/Users/mikewolfd/Work/popcorn-xp/hooks/scripts/update-task-registry.sh)

Suggested new name:

- `update-task-state.sh`

#### Why

The script is no longer maintaining a registry. It updates explicit per-agent state. The current name preserves outdated architecture and makes the system harder to understand.

The runtime value is real:

- it synchronizes claims and completions into `agent-state/*.json`
- other hooks depend on that state

The functionality should stay. The name should catch up.

### 9. Keep the Retro Gate and Cleanup

Keep:

- [check-retro-before-delete.sh](/Users/mikewolfd/Work/popcorn-xp/hooks/scripts/check-retro-before-delete.sh)
- [cleanup-context-store.sh](/Users/mikewolfd/Work/popcorn-xp/hooks/scripts/cleanup-context-store.sh)

#### Why

These hooks are cheap and correspond to clear lifecycle requirements:

- do not delete the team before a retro exists
- clean up shared context-store artifacts after deletion

#### Minor Fix

The comment in `check-retro-before-delete.sh` claims it checks whether `RETRO.md` was updated "this session." The code only checks existence and minimum line count. The comment should be corrected to match reality.

### 10. Keep Compaction Retirement, With One Optional Simplification

Keep:

- [record-compact-summary.sh](/Users/mikewolfd/Work/popcorn-xp/hooks/scripts/record-compact-summary.sh)

Optional:

- remove [mark-compact-pending.sh](/Users/mikewolfd/Work/popcorn-xp/hooks/scripts/mark-compact-pending.sh) if a smaller compaction path is preferred

#### Why

`record-compact-summary.sh` has clear lifecycle value:

- preserve the compact summary
- queue controlled retirement

`mark-compact-pending.sh` is coherent and low-frequency, but optional. If the goal is fewer moving parts, compaction can be simplified by relying on PostCompact state only.

## Recommended Target Hook Surface

If the proposal is accepted, the target runtime hook surface should be:

- `TaskCompleted`
  - `check-advice-on-complete.sh`
- `TeammateIdle`
  - `enforce-no-idle.sh`
- `PreCompact`
  - optional `mark-compact-pending.sh`
- `PostCompact`
  - `record-compact-summary.sh`
- `PreToolUse TeamDelete`
  - `check-retro-before-delete.sh`
- `PreToolUse Read`
  - none, or a narrow dirty-only `context-store-check.sh`
- `PreToolUse Edit|Write`
  - `context-store-mark-dirty.sh`
- `PreToolUse TaskUpdate`
  - `check-task-claim.sh`
- `PostToolUse TeamDelete`
  - `cleanup-context-store.sh`
- `PostToolUse TaskUpdate`
  - renamed `update-task-state.sh`

Helper scripts:

- `session-common.sh`
- `context-store-log.sh`

Deleted:

- `notify-retro-written.sh`
- `notify-retro-received.sh`
- `check-rotation.sh`
- `check-objections.sh`
- `remind-unread-advice.sh`
- `remind-checkpoint.sh`
- likely `context-store-update-read.sh`
- likely `context-store-check.sh` in its current form

## Why This Is Better

### Fewer Hot-Path Hook Executions

The current system spends hook budget on read-time narration and split idle enforcement. The proposed system spends hook budget on:

- hard invariants
- edit coordination
- lifecycle transitions

That is a better trade.

### Less Context Noise

Clean-read context injection is almost pure token tax. The proposal removes or narrows that path and keeps only file-activity signals that are meaningfully actionable.

### Stronger Semantics

A hook should answer a question with confidence. Examples:

- "Can this task be completed?" Yes, by checking unresolved `OBJECTION`s.
- "Can this teammate claim a task?" Yes, by checking shutdown and current task state.
- "Is someone else actively editing this file?" Yes, by checking recent edit state.

The current read-side context store answers weaker questions and therefore produces weaker value.

### Better Alignment With The Intended Collaboration Model

The protocol says:

- communicate live via `SendMessage`
- persist typed advice in `ADVICE.md`
- persist progress in `LOG.md`
- use explicit agent state for machine coordination

The proposal brings the hook layer closer to that model instead of layering side channels on top of it.

## Migration Notes

If this proposal is implemented:

1. Remove dead scripts first.
2. Merge checkpoint and advice idle logic into `enforce-no-idle.sh`.
3. Rename `update-task-registry.sh` to reflect actual behavior.
4. Delete or narrow the read-side context store hooks.
5. Update [docs/architecture/architecture.md](../architecture/architecture.md), [README.md](../../README.md), [CLAUDE.md](../../CLAUDE.md), and tests to match the reduced hook surface.

## Bottom Line

This proposal does not argue for a softer system.

It argues for a smaller, sharper one.

The hooks that remain should be the ones whose absence would be immediately felt:

- completion gates
- claim guards
- idle-state enforcement
- edit coordination
- retro and compaction lifecycle handling

Everything else should be treated skeptically and removed unless it can justify its runtime cost with a behavior the system truly depends on.
