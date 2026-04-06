# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

Popcorn XP is a Claude Code plugin that implements XP pair programming for agent teams. The working trio is **one driver, one navigator, one advisor** — **current, future, and past** respectively: the driver edits the present task; the navigator reads ahead and steers via typed advice; the advisor reviews what already landed (tests, regressions). Driver and navigator rotate between tasks; the advisor is the standing reviewer unless you rotate that seat by design.

**Dual runtime mode** (`.popcorn-xp/{team}/.runtime-mode`): **`subagent`** is the **recommended default** (also the default when `.runtime-mode` is **omitted**) — lead keeps normal tools and orchestrates subagents; file task bus via `bin/session` (`task-init|task-claim [expected-rev]|task-revision|task-advisor-scope|task-release|task-complete|task-abandon|chat|cursor-*|health|close-check|close [--force]`, etc.); team-only hooks no-op; `SubagentStop` runs OBJECTION + non-blocking advice/compaction hints; append-only **`events.jsonl`**. **`team`** (Agent Teams, `TaskUpdate`, context-store, `TeammateIdle`) uses a **coordinator-only lead** (no file tools) and peer **`SendMessage`** — **explicit opt-in**; avoid steering new sessions there until a **Claude Code bug** causing **extreme token use** in team mode is fixed. See `docs/dual-mode-proposal.md` and `skills/popcorn-xp/SKILL.md`.

Runtime is Claude Code. **`team`** mode requires Agent Teams (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`) and Coordinator Mode (`CLAUDE_CODE_COORDINATOR_MODE=1`) for the lead. **`subagent`** mode does not require the lead to run coordinator-only (subagents still run under normal agent tooling).

**OpenAI Codex:** Reference integration lives under `.codex/` and `codex/` (hooks, layered skills, example agents). See `docs/dual-mode-codex-companion.md` and `codex/README.md`. Tests cover Codex shims as `CX-*` in `./tests/test-hooks.sh`.

## Running Tests

```bash
./tests/test-hooks.sh
```

Single test file, no external dependencies beyond bash 4+. Tests validate all hook scripts against canonical exit code semantics:

- Exit 0 = allow (stdout JSON with `additionalContext` for non-blocking feedback)
- Exit 2 = block (stderr plain text fed to Claude as feedback)

## Architecture

### Plugin Structure

`plugin.json` registers three plugin components: `agents/` (teammate definitions), `skills/` (lead workflow + protocol), `hooks/hooks.json` (lifecycle enforcement).

### Two Skills, Different Audiences

- **`skills/popcorn-xp/SKILL.md`** — The lead's playbook. Loaded when a user triggers a session ("popcorn this task"). Contains full workflow: team creation, task breakdown, teammate spawning, monitoring, shutdown lifecycle. The lead follows this.
- **`skills/popcorn-xp-protocol/SKILL.md`** — The teammate protocol. Auto-loaded into every popcorn-xp agent via the `skills` field in agent frontmatter. Contains core rules, advice lifecycle, advice format, session file conventions. Native agents from other plugins load this via `Skill('popcorn-xp-protocol')`.

### Hook System

`hooks/hooks.json` registers hooks on lifecycle and tool use events. All hooks are no-ops when no `.popcorn-xp/.active-team` exists.

When `.popcorn-xp/{team}/.runtime-mode` is **`subagent`**, these hooks exit 0 immediately (team transport not used): `context-store-check.sh`, `context-store-mark-dirty.sh`, `check-task-claim.sh`, `update-task-state.sh`. **`check-retro-before-delete.sh`** and **`cleanup-context-store.sh`** also no-op in subagent mode (closeout is `session close-check` / `session close`, not `TeamDelete`). `enforce-no-idle.sh` still runs **retro / shutdown / compaction** gates; working-phase nudges skip context-store; **advisors** use task chat vs `.review-cursor-*`; **navigators** in `waiting_on_driver` must **cursor-ack** task chat (meta cursors). Agents with no `agent-state` registration (or empty role and phase) skip working nudges. `SubagentStop` runs `check-advice-on-subagent-stop.sh`.

| Event | Script | Purpose |
|-------|--------|---------|
| TaskCompleted | `check-advice-on-complete.sh` | Blocks on unresolved OBJECTIONs, warns on open SMELLs/STEERs/FYIs |
| SubagentStop | `check-advice-on-subagent-stop.sh` | OBJECTION gate + open SMELL/STEER/FYI warnings + compaction-pending hint when mode is `subagent` |
| TeammateIdle | `enforce-no-idle.sh` | Phase-aware idle enforcement with checkpoint and advice checks, debounce, and shutdown lifecycle |
| PreCompact | `mark-compact-pending.sh` | Records compaction event for controlled retirement |
| PostCompact | `record-compact-summary.sh` | Preserves compact summary and queues retirement |
| PreToolUse(Read) | `context-store-check.sh` | Warns when reading a file dirty-edited by another agent (cross-agent only) |
| PreToolUse(Edit/Write) | `context-store-mark-dirty.sh` | Marks file dirty on edit; warns if another agent is actively editing (soft lock) |
| PreToolUse(TeamDelete) | `check-retro-before-delete.sh` | Blocks TeamDelete until RETRO.md exists with >= 5 lines |
| PreToolUse(TaskUpdate) | `check-task-claim.sh` | Blocks claims after shutdown; blocks claiming while already driving |
| PostToolUse(TeamDelete) | `cleanup-context-store.sh` | Removes shared context-store artifacts after team deletion |
| PostToolUse(TaskUpdate) | `update-task-state.sh` | Synchronizes task claims/completions into agent-state/*.json |

### Context Store (Soft Lock)

The context store enables cross-agent awareness of file edits during pair programming:

**Store Location**: `.popcorn-xp/context-store.log` (append-only log; no JSON store)

**Tracking**: All state derived from the log. Each EDIT event records the agent name, file path, and timestamp. The last EDIT event for a given file determines the current editor.

**Soft Lock Behavior**: When an agent reads a file that was last edited by a different agent, the context store check hook injects a warning. Files with no EDIT in the log, and same-agent edits, produce no output.

**Event Log**: `.popcorn-xp/context-store.log` records edit and read events with agent names, file paths, and lock status. Used by `enforce-no-idle.sh` for checkpoint counting and by context-store hooks for soft lock detection.

### Session Files (Runtime)

Created at `.popcorn-xp/{team-name}/` during session setup. Gitignored.

- `LOG.md` — Append-only checkpoint log
- `ADVICE.md` — Append-only advice ledger (advice entries + resolution entries)
- `RETRO.md` — Accumulated retrospectives across sessions
- `.runtime-mode` — `team` or `subagent` (default **`subagent`** if missing; write `team` to opt into Agent Teams)
- `tasks/T{n}/meta.json` & `tasks/T{n}/back-forth.md` — Subagent task bus (subagent mode)
- `.closed.json` — Written by `session close` (subagent closeout marker)
- `session` — Thin wrapper that execs `bin/session` (the canonical session helper)
- `.active-team` — Contains current team name (at `.popcorn-xp/.active-team`)
- `agent-state/*.json` — Per-agent machine-readable state (role, phase, task, write set)
- Signal files: `.retro-requested`, `.retro-{agent}.md`, `.shutdown`, `.checkpoint-cursor`

### Paired Task Model

Every logical task becomes two tasks: a drive task and a navigate task. This makes pairing structural — a drive task without a matching navigate task is a visible gap. The navigator stays active through the driver's full cycle and completes after verifying the driver's finished work. Rotation is encoded in the assignments: the T1 navigator claims T2's drive task, and vice versa.

### Advice Resolution Model

ADVICE.md is an append-only ledger. Hooks determine unresolved items by checking which IDs from `### TYPE ID — open` lines lack a matching `### ID — OUTCOME` resolution line. Resolution matching is case-insensitive. Valid outcomes: FIXED, REJECTED, INCORPORATED, NOTED.

### Agent Definitions

All agents in `agents/` share the same structure: YAML frontmatter with `name`, `description`, `model`, `color`, `skills: [popcorn-xp-protocol]`, followed by a lens description and behavioral instructions. The `skills` field auto-loads the protocol into each agent's context.

### Shutdown Lifecycle (R4)

Four-phase lifecycle enforced by `enforce-no-idle.sh` reading signal files:

1. **Retro pending** (`.retro-requested`, no `.retro-{agent}.md`) — nudge retro submission (takes priority over shutdown so agents can write retros before being stopped)
2. **Shutdown** (`.shutdown` exists, retro done or never requested) — remind agent to approve shutdown_request from the lead (exit 2)
3. **Retro done** (both exist, no `.shutdown`) — allow idle, wait for shutdown
4. **Working** (default) — nudge agent to find work

## Key Conventions

- Hook scripts use `$CLAUDE_PROJECT_DIR` (set by Claude Code) to find `.popcorn-xp/`.
- `bin/session` is the canonical session helper. A thin wrapper at `.popcorn-xp/{team}/session` execs it. Subagent mode adds `task-init`, `task-claim`, `task-release`, `task-complete`, `task-abandon`, `chat`, `chat-read`, `cursor-get`, `cursor-ack`, `health` (`--strict` optional), `close-check` (OBJECTIONs, locks, open task-bus claims, retro-or-handoff when `.retro-requested`, compaction handoffs), `close` (after `close-check`, requires `RETRO.md` with ≥5 lines; `close --force` skips `close-check` and `RETRO.md`), and `mode`. Optional: **`POPCORN_XP_EVENT_LOG_DEBUG`** — `events.jsonl` append failures print to stderr.
- `session log` advances the checkpoint cursor from `context-store.log` line count in **team** mode only; in **subagent** mode it only appends to LOG.md.
- Context store agent names follow `popcorn-xp:<agent-name>` convention (prefixed by hooks).
- `references/protocol.md` contains teammate prompt templates (driver, navigator, advisor) that the lead includes when spawning agents. This is the detailed version; the protocol skill is the condensed version auto-loaded into agents.
- `research/` contains background research on Claude Code features. Not loaded at runtime.
