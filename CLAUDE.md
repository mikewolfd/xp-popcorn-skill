# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

Popcorn XP is a Claude Code plugin that implements XP pair programming for agent teams. It launches 2-3 autonomous Claude Code agents that pair-program: one driver edits code, one navigator steers via typed advice, and they rotate roles between tasks. The lead (orchestrator) runs in coordinator mode with no file access.

Runtime is Claude Code only. Requires Agent Teams (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`) and Coordinator Mode (`CLAUDE_CODE_COORDINATOR_MODE=1`).

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

`hooks/hooks.json` registers hooks on five events. All hooks are no-ops when no `.popcorn-xp/.active-team` exists.

| Event | Script | Purpose |
|-------|--------|---------|
| TaskCompleted | `check-advice-on-complete.sh` | Blocks on unresolved OBJECTIONs, warns on open SMELLs/STEERs/FYIs |
| TaskCompleted | `check-rotation.sh` | Warns when same agent drives all completed tasks |
| SubagentStop | `check-objections.sh` | Backup block on unresolved OBJECTIONs |
| TeammateIdle | `remind-unread-advice.sh` | Reminds agent of open advice items |
| TeammateIdle | `remind-checkpoint.sh` | Reminds driver to checkpoint after edits |
| TeammateIdle | `enforce-no-idle.sh` | Phase-aware: working→nudge, retro-pending→nudge retro, retro-done→allow, shutdown→force-stop |
| PreToolUse(Edit/Write) | `mark-dirty.sh` | Counts uncheckpointed edits, soft reminder after 3+ |
| PreToolUse(TeamDelete) | `check-retro-before-delete.sh` | Blocks TeamDelete until RETRO.md exists with >= 5 lines |

### Session Files (Runtime)

Created at `.popcorn-xp/{team-name}/` during session setup. Gitignored.

- `LOG.md` — Append-only checkpoint log
- `ADVICE.md` — Append-only advice ledger (advice entries + resolution entries)
- `RETRO.md` — Accumulated retrospectives across sessions
- `session` — Bash helper script teammates call to append entries (never edit files directly)
- `.active-team` — Contains current team name (at `.popcorn-xp/.active-team`)
- Signal files: `.dirty`, `.edit-count`, `.retro-requested`, `.retro-{agent}.md`, `.shutdown`

### Advice Resolution Model

ADVICE.md is an append-only ledger. Hooks determine unresolved items by checking which IDs from `### TYPE ID — open` lines lack a matching `### ID — OUTCOME` resolution line. Resolution matching is case-insensitive. Valid outcomes: FIXED, REJECTED, INCORPORATED, NOTED.

### Agent Definitions

All agents in `agents/` share the same structure: YAML frontmatter with `name`, `description`, `model`, `color`, `skills: [popcorn-xp-protocol]`, followed by a lens description and behavioral instructions. The `skills` field auto-loads the protocol into each agent's context.

### Shutdown Lifecycle (R4)

Four-phase lifecycle enforced by `enforce-no-idle.sh` reading signal files:
1. **Retro pending** (`.retro-requested`, no `.retro-{agent}.md`) — nudge retro submission (takes priority over shutdown so agents can write retros before being stopped)
2. **Shutdown** (`.shutdown` exists, retro done or never requested) — force-stop via `{"continue": false}`
3. **Retro done** (both exist, no `.shutdown`) — allow idle, wait for shutdown
4. **Working** (default) — nudge agent to find work

## Key Conventions

- Hook scripts use `$CLAUDE_PROJECT_DIR` (set by Claude Code) to find `.popcorn-xp/`.
- The `session` script is the only interface teammates use to write to LOG.md and ADVICE.md.
- `session log` resets `.dirty` and `.edit-count` (checkpoint clears the edit counter).
- `references/protocol.md` contains teammate prompt templates (driver, navigator, advisor) that the lead includes when spawning agents. This is the detailed version; the protocol skill is the condensed version auto-loaded into agents.
- `research/` contains background research on Claude Code features. Not loaded at runtime.
