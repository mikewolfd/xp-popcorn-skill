# Popcorn XP Architecture

How the skills, agents, hooks, and session files work together end to end.

## The Three Layers

Popcorn XP has three layers that collaborate at runtime:

| Layer | What it is | Where it lives |
|-------|-----------|----------------|
| **Skills** | Prompts that tell agents what to do | `skills/` |
| **Agents** | Personality definitions with a lens and behavioral instructions | `agents/` |
| **Hooks** | Bash scripts that enforce rules mechanically | `hooks/scripts/` |

Skills provide intent. Agents provide perspective. Hooks provide guarantees.

## Session Lifecycle

### Trigger

A user says something like "popcorn this task" or "pair program on this." The lead's Claude Code session loads `skills/popcorn-xp/SKILL.md` — the lead's playbook.

The lead runs in **coordinator mode**: it cannot read or edit files. It can only create teams, create tasks, spawn agents, and send messages.

### Setup (SKILL.md Steps 1-4)

1. **Understand the task** — the lead reads relevant code (via a research worker if in coordinator mode) and builds a mental model
2. **Create the team** — `TeamCreate`, then set up `.popcorn-xp/{team-name}/` with LOG.md, ADVICE.md, and the `session` helper script. The lead asks the user which model to use and which agents to roster.
3. **Create tasks** — 5-8 tasks with dependency chains via TaskCreate/TaskUpdate. Aggressive decomposition: one verb, one goal, one set of files per task.
4. **Spawn teammates** — 2-3 agents from the roster. The initial driver/navigator pair starts; others join from the bench as tasks demand them.

### Execution (SKILL.md Step 5)

Teammates pair-program directly with each other via SendMessage. The lead monitors but does not drive:

- Rotation self-progresses: navigator becomes driver, driver becomes navigator
- The lead steers on exceptions: wrong agent claimed, scope changed, stuck task
- Periodic code review: the lead launches `code-reviewer` independently every 2-3 tasks and relays findings

### Shutdown (SKILL.md Step 6)

A four-phase mechanical shutdown, mediated by signal files and `enforce-no-idle.sh`:

```
1. Lead calls `session retro-request`     → creates .retro-requested
2. Lead SendMessages each agent for retro
3. enforce-no-idle sees retro-pending      → nudges idle agents to write retro
4. Agents write retros via `session retro` → creates .retro-{agent}.md
5. notify-retro-written nudges agent       → agent SendMessages the lead
6. notify-retro-received tells the lead    → FileChanged hook fires
7. Lead calls `session shutdown`           → creates .shutdown
8. enforce-no-idle sees shutdown            → force-stops agents via {"continue": false}
9. Lead writes RETRO.md
10. check-retro-before-delete gates cleanup → blocks TeamDelete until RETRO.md exists
11. Lead calls TeamDelete
```

## Agents

Each agent in `agents/` is a Markdown file with YAML frontmatter:

```yaml
name: popcorn-xp:craftsman
description: "..."
color: blue
skills:
  - popcorn-xp-protocol
```

The `skills: [popcorn-xp-protocol]` field auto-loads the protocol into every agent at startup. Agents don't need to be told the collaboration rules — the rules arrive automatically.

Each agent has a **lens** — a question they filter everything through:

| Agent | Lens |
|-------|------|
| `scout` | "Are we solving the right problem?" |
| `craftsman` | "Is this clean and readable?" |
| `expert` | "Does this actually work in edge cases?" |
| `tester` | "How will we prove this works?" |
| `service-designer` | "Does the interface serve the experience?" |
| `visual-designer` | "Does this look right and feel right?" |
| `qa` | "Does this work from the user's perspective?" |
| `product-manager` | "What problem are we solving?" |
| `code-reviewer` | "What does this code actually do, and can I prove it?" |

The lens shapes how an agent thinks, not what it's allowed to do. Any agent can drive, navigate, write tests, or review code.

**The code-reviewer is special.** It is NOT a teammate. It's spawned independently by the lead (no `team_name`) for periodic reviews. It produces a structured review certificate. The lead relays its findings to the team as OBJECTIONs/SMELLs.

### Native Agent Support

Native agents from other plugins (e.g., `test-engineer`, `flutter-architect`) can fill persona slots. They load the protocol via `Skill('popcorn-xp-protocol')` as their first action. Their domain-specific instructions come from their own definition; the protocol adds collaboration rules on top.

## Skills

### `skills/popcorn-xp/SKILL.md` — The Lead's Playbook

Loaded when the user triggers a session. Contains the full workflow: team creation, task breakdown, teammate spawning, monitoring, shutdown lifecycle. Only the lead follows this.

### `skills/popcorn-xp-protocol/SKILL.md` — The Teammate Protocol

Auto-loaded into every popcorn-xp agent via the `skills` field. Contains:

- **Core rules**: one driver at a time, task ownership is the lock, no idle hands, commit before rotating
- **Advice lifecycle**: four types (OBJECTION, SMELL, STEER, FYI) with different blocking behavior
- **ADVICE.md format**: append-only ledger with open/resolution entries
- **Session file conventions**: how to use LOG.md, ADVICE.md, the `session` script
- **Rotation**: driver commits, becomes navigator; navigator claims next task, becomes driver
- **Retro**: process observations only, not task summaries

## Hooks

All hooks are registered in `hooks/hooks.json`. Every hook checks for `.popcorn-xp/.active-team` first — if no session is active, it exits 0 (no-op).

### Hook Inventory

#### PreToolUse — Edit/Write

| Script | Purpose | Behavior |
|--------|---------|----------|
| `mark-dirty.sh` | Counts uncheckpointed edits | Increments `.edit-count`, sets `.dirty`. After 3+ edits, injects soft reminder. Resets when agent runs `session log`. |
| `context-store-mark-dirty.sh` | Records edit in shared context store | Marks file dirty in `context-store.json`. If another agent is editing the same file, injects soft-lock warning. |

#### PreToolUse — Read

| Script | Purpose | Behavior |
|--------|---------|----------|
| `context-store-check.sh` | Cross-agent file awareness | Checks if file was previously read/edited. Injects cache-hit metadata (who, when, dirty status). |

#### PreToolUse — TeamDelete

| Script | Purpose | Behavior |
|--------|---------|----------|
| `check-retro-before-delete.sh` | Gates cleanup on retro | Blocks (exit 2) unless RETRO.md exists with 5+ lines. |

#### PostToolUse — Read

| Script | Purpose | Behavior |
|--------|---------|----------|
| `context-store-update-read.sh` | Records read in context store | Writes agent name, timestamp, and file preview to `context-store.json`. Initializes store if needed. |

#### PostToolUse — Write

| Script | Purpose | Behavior |
|--------|---------|----------|
| `notify-retro-written.sh` | Nudges agent after retro write | If written file matches `.retro-*.md`, injects "SendMessage the lead to confirm." |

#### TaskCompleted

| Script | Purpose | Behavior |
|--------|---------|----------|
| `check-advice-on-complete.sh` | Enforces OBJECTION engagement | Blocks (exit 2) if unresolved OBJECTIONs exist. Warns (additionalContext) about open SMELLs/STEERs/FYIs. |
| `check-rotation.sh` | Warns about missing rotation | If all completed tasks had the same driver, injects rotation warning. |

#### TeammateIdle

| Script | Purpose | Behavior |
|--------|---------|----------|
| `remind-unread-advice.sh` | Reminds agent of open advice | Counts unresolved items by type. Blocks (exit 2) with summary. |
| `remind-checkpoint.sh` | Reminds driver to checkpoint | If `.dirty` is set, blocks (exit 2) with edit count. Clears flags after reminding. |
| `enforce-no-idle.sh` | Phase-aware idle enforcement | Four phases checked in priority order (see below). |

#### SubagentStop

| Script | Purpose | Behavior |
|--------|---------|----------|
| `check-objections.sh` | Backup OBJECTION check | Blocks (exit 2) if unresolved OBJECTIONs exist. Safety net for when a teammate stops without completing a task. |

#### FileChanged — `.retro-*.md`

| Script | Purpose | Behavior |
|--------|---------|----------|
| `notify-retro-received.sh` | Tells lead a retro arrived | Counts collected retros, injects context for the lead. |

### Helper (not a hook)

| Script | Purpose |
|--------|---------|
| `context-store-log.sh` | Sourced by context-store hooks. Provides `cs_log()` for appending events to `context-store.log`. |

### enforce-no-idle.sh Phases

The core enforcement hook. Checked in priority order:

| Phase | Condition | Action |
|-------|-----------|--------|
| 1. Retro pending | `.retro-requested` exists, `.retro-{agent}.md` missing | Nudge retro (exit 2) |
| 2. Shutdown | `.shutdown` exists, retro done or never requested | Force-stop via `{"continue": false}` (exit 0) |
| 3. Retro done | Both exist, no `.shutdown` | Allow idle (exit 0) |
| 4. Working | Default | Nudge "go find work" (exit 2) |

Phase 1 taking priority over phase 2 is critical — it ensures agents can write retros before being stopped, even if `.shutdown` is already set.

### Hook Exit Code Semantics

| Exit Code | Meaning | Output Channel |
|-----------|---------|----------------|
| 0 | Allow | stdout JSON with `additionalContext` for non-blocking feedback |
| 2 | Block | stderr plain text, fed to Claude as feedback |

## Session Files

Created at `.popcorn-xp/{team-name}/` during setup. Gitignored.

### Persistent Files

| File | Purpose | Written by |
|------|---------|------------|
| `LOG.md` | Append-only checkpoint log | Teammates via `session log` |
| `ADVICE.md` | Append-only advice ledger (advice + resolutions) | Teammates via `session advice` / `session resolve` |
| `RETRO.md` | Accumulated retros across sessions | Lead after shutdown |
| `session` | Bash helper script — the only interface for writing to LOG.md and ADVICE.md | Lead creates at setup |

### Signal Files

| File | Purpose | Created by | Read by |
|------|---------|------------|---------|
| `.active-team` | Contains current team name | Lead at setup (at `.popcorn-xp/.active-team`) | Every hook |
| `.dirty` | Flag: uncheckpointed edits exist | `mark-dirty.sh` | `remind-checkpoint.sh` |
| `.edit-count` | Counter: number of edits since last checkpoint | `mark-dirty.sh` | `remind-checkpoint.sh` |
| `.retro-requested` | Flag: lead has asked for retros | `session retro-request` | `enforce-no-idle.sh` |
| `.retro-{agent}.md` | Agent's retro observations | `session retro` | `enforce-no-idle.sh`, `notify-retro-received.sh` |
| `.shutdown` | Flag: lead has initiated shutdown | `session shutdown` | `enforce-no-idle.sh` |

### The `session` Script

The only interface teammates use for session file writes. Commands:

| Command | What it does |
|---------|-------------|
| `session log "message"` | Appends checkpoint to LOG.md. Clears `.dirty` and `.edit-count`. |
| `session advice TYPE ID "description"` | Appends advice entry to ADVICE.md (idempotent — skips if ID exists). |
| `session resolve ID OUTCOME "detail"` | Appends resolution entry to ADVICE.md. |
| `session task ID DRIVER NAV` | Appends task header to LOG.md. |
| `session handoff AGENT` | Creates handoff template at `handoff-{agent}.md`. |
| `session retro-request` | Creates `.retro-requested` signal file. |
| `session retro AGENT "observations"` | Writes retro to `.retro-{agent}.md`. |
| `session shutdown` | Creates `.shutdown` signal file. |

## Advice Resolution Model

ADVICE.md is an append-only ledger. Three hooks determine unresolved items using the same logic:

- Advice entries: `### TYPE ID — open`
- Resolution entries: `### ID — OUTCOME`
- An item is unresolved if its ID appears in an "open" line but NOT in an OUTCOME line
- Resolution matching is case-insensitive
- Valid outcomes: FIXED, REJECTED, INCORPORATED, NOTED

REJECTED is a first-class outcome. A driver who rejects an OBJECTION with sound reasoning has used the system correctly.

| Type | Blocks task completion? | What it means |
|------|------------------------|---------------|
| OBJECTION | Yes — hard block | Something is factually wrong. Must engage: fix or reject with reasoning. |
| SMELL | No — reminder | Something looks off. Read it, use your judgment. |
| STEER | No — reminder | Different approach suggested. Consider it. |
| FYI | No — reminder | Observation. Note if relevant. |

## Context Store

`context-store.json` at `.popcorn-xp/context-store.json` enables cross-agent file awareness.

Three hooks maintain it:
- `context-store-check.sh` (PreToolUse Read) — reads from the store, injects metadata
- `context-store-mark-dirty.sh` (PreToolUse Edit/Write) — marks files dirty, detects soft locks
- `context-store-update-read.sh` (PostToolUse Read) — records reads with full preview

Each file entry tracks:

```json
{
  "path/to/file": {
    "read_by": "popcorn-xp:craftsman",
    "read_at": "2026-04-03T14:30:00Z",
    "dirty": true,
    "edited_by": "popcorn-xp:expert",
    "edited_at": "2026-04-03T14:32:00Z",
    "offset": null,
    "limit": null,
    "preview": "file content..."
  }
}
```

The soft lock is informational, not blocking. When agent A reads a file marked dirty by agent B, the hook injects a warning but allows the read. Uses `lockf` for mutual exclusion on macOS.

`context-store.log` records all read/edit events with timestamps, agent names, and file paths.

## Hook Scoping

All hooks currently fire globally — whenever the plugin is enabled, on every Claude Code session in this project. Each hook guards itself with a `.active-team` check, exiting 0 (no-op) when no session is active.

Per the [hooks documentation](https://docs.anthropic.com/en/docs/claude-code/hooks), hooks can be scoped to agents via frontmatter:

| Location | Scope |
|----------|-------|
| `~/.claude/settings.json` | All projects |
| `.claude/settings.json` | Single project |
| Plugin `hooks/hooks.json` | When plugin is enabled |
| **Skill or agent frontmatter** | **While the skill or agent is active** |

Hooks that only make sense for teammates (mark-dirty, context-store-*, remind-*, enforce-no-idle) could be moved to agent frontmatter to eliminate unnecessary no-op executions during solo use. Hooks that fire on the lead (check-retro-before-delete, notify-retro-received, check-rotation) would stay in hooks.json or the lead skill.
