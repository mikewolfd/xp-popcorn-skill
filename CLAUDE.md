# CLAUDE.md

Project guidance for **Claude Code** (claude.ai/code), **OpenAI Codex** (CLI / app), and any tool that loads this file (including **`AGENT.md`**, a symlink here). Same pairing model and session files everywhere; packaging and transport differ by product.

## What This Is

Popcorn XP is a plugin-shaped workflow for XP pair programming with agent teams. The working trio is **one driver, one navigator, one advisor** — **current, future, and past** respectively: the driver edits the present task; the navigator reads ahead and steers via typed advice; the advisor reviews what already landed (by default through the **scout** scope-and-constraints lens; **tester** when verification-led). Driver and navigator rotate between tasks; the advisor is the standing reviewer unless you rotate that seat by design.

**Dual runtime mode** (`.popcorn-xp/{team}/.runtime-mode`): **`subagent`** is the **recommended default** (also the default when `.runtime-mode` is **omitted**) — lead keeps normal tools and orchestrates workers; file task bus via `shared/runtime/bin/session` (`task-init|task-claim [expected-rev]|task-revision|task-advisor-scope|task-release|task-complete|task-abandon|chat|cursor-*|health|close-check|close [--force]`, etc.); **`SubagentStop`** runs OBJECTION + non-blocking advice/compaction hints; append-only **`events.jsonl`**. **`team`** (**Claude Code** only today: Agent Teams, `TaskUpdate`, context-store, `TeammateIdle`) uses a **coordinator-only lead** (no file tools) and peer **`SendMessage`** — **explicit opt-in**; avoid steering new sessions there until a **Claude Code bug** causing **extreme token use** in team mode is fixed.

**Claude Code — two plugins (enable only one):** **`popcorn-xp`** (`platforms/claude/popcorn-xp/`) ships **subagent** hooks (`SubagentStop`, `TeammateIdle`, compaction). **`popcorn-xp-team`** (`platforms/claude/popcorn-xp-team/`) ships **Agent Teams** hooks (`TaskCompleted`, `TaskUpdate`, context-store, `TeamDelete`, plus `SubagentStop` for lead subagents). Shared hook scripts and teammate agents live under **`shared/`** (symlinked into each plugin). `.claude-plugin/marketplace.json` lists both sources. See `docs/dual-mode-proposal.md`, `platforms/claude/popcorn-xp/skills/popcorn-xp/SKILL.md`, and `platforms/claude/popcorn-xp-team/skills/popcorn-xp-team/SKILL.md`.

**Claude Code:** The hook table below lists **all** scripts; rows for `TaskUpdate`, context-store, and `TeamDelete` apply only when **`popcorn-xp-team`** is installed. **`team`** mode needs Agent Teams (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`) and Coordinator Mode (`CLAUDE_CODE_COORDINATOR_MODE=1`) for the lead — set both in **`~/.claude/settings.json`** under **`env`**, then restart Claude Code. **Not required** for the default **`popcorn-xp`** (subagent) plugin. **`subagent`** mode does not require the lead to be coordinator-only (subagents still use normal agent tooling).

**Codex:** Treat this repo as **`subagent`-first** — same `shared/runtime/bin/session`, `LOG.md`, `ADVICE.md`, task bus, and closeout story; no Claude-style Agent Teams / `TaskUpdate` transport in the captured product docs. Hooks are wired through **`platforms/codex/subagent/manifests/hooks.json`** → **`platforms/codex/subagent/hooks/*.sh`** (for example **`Stop`** instead of **`SubagentStop`**); read **`platforms/codex/subagent/skills/popcorn-xp/SKILL.md`** (Codex lead playbook — **source:** **`shared/skill-sources/codex-lead/*.md`** via **`./scripts/build-skills.sh`**), **`platforms/codex/subagent/README.md`**, and **`docs/architecture/dual-mode-codex-companion.md`** for gaps vs the Claude hook table. Layered skills for teammates live under **`platforms/codex/subagent/skills/`**. Tests cover Codex direct-tree hooks as **`CX-*`** in **`./tests/test-hooks.sh`**.

## Running Tests

```bash
./scripts/build-skills.sh   # refresh generated SKILL.md (teammate/, lead-playbook/, codex-lead/) — required before commit if you edited sources
./tests/test-hooks.sh
./tests/claude-plugin-test-harness.sh   # includes a drift check: generated skills must match git index after build
```

Single test file, no external dependencies beyond bash 4+. Tests validate all hook scripts against canonical exit code semantics:

- Exit 0 = allow (stdout JSON with `additionalContext` for non-blocking feedback)
- Exit 2 = block (stderr plain text surfaced to the user / host agent as feedback)

## Architecture

### Plugin Structure

**Claude Code:** Default plugin **`popcorn-xp`** registers subagent hooks, lead skill **`popcorn-xp`**, symlinked **`agents/`** and **`popcorn-xp-protocol`**, and **`.claude-plugin/plugin.json`** (id **`popcorn-xp`**). Optional plugin **`popcorn-xp-team`** registers Agent Teams hooks, lead skill **`popcorn-xp-team`**, the same shared agents, and its own protocol variant (core + subagent + team transport). **Do not enable both plugins** (duplicate hook handlers).

**Codex:** Parallel layout under **`platforms/codex/subagent/`** plus generated **`.codex/`** install output — see **`platforms/codex/subagent/README.md`**.

### Skills (Claude)

- **`platforms/claude/popcorn-xp/skills/popcorn-xp/SKILL.md`** — Lead playbook for **file-bus / subagent** transport (default). **Source:** fragments under **`shared/skill-sources/lead-playbook/`**; regenerate with **`./scripts/build-skills.sh`** (do not edit generated output by hand).
- **`platforms/claude/popcorn-xp-team/skills/popcorn-xp-team/SKILL.md`** — Lead playbook for **Agent Teams** transport (`popcorn-xp-team` plugin). Same build script and fragment layout.
- **`shared/skills/popcorn-xp-protocol/SKILL.md`** — Teammate protocol: core rules + subagent transport (symlinked into `popcorn-xp` plugin and Codex). **Source:** **`shared/skill-sources/teammate/*.md`** via **`./scripts/build-skills.sh`**. Auto-loaded via agent frontmatter `skills: [popcorn-xp-protocol]`. Native agents: `Skill('popcorn-xp-protocol')`. On **Codex**, **`[[skills.config]]`** points at **`platforms/codex/subagent/skills/popcorn-xp-protocol/`** (symlink to shared). The **`popcorn-xp-team`** plugin has its own generated copy that adds Agent Teams transport.

### Hook System

**Claude Code:** Hook sets are split by plugin — **`popcorn-xp/hooks/hooks.json`** (subagent) vs **`popcorn-xp-team/hooks/hooks.json`** (team + `SubagentStop`). Scripts live in **`shared/hooks/scripts/`** under **`advice/`**, **`team/`** (Agent Teams + context store), and **`lifecycle/`** (idle + compaction). All hooks no-op when no `.popcorn-xp/.active-team` exists.

**Codex:** Only a subset of events exists in the upstream product (see **`research/official/codex/hooks.md`**); this repo’s hooks bridge **`SessionStart`** / **`Stop`** to the same bash contracts where possible. Do not assume every row in the table below has a Codex equivalent — use **`docs/architecture/dual-mode-codex-companion.md`** as the mapping.

With **`popcorn-xp-team`** installed and `.runtime-mode` **`team`**, team hooks run as written. With only **`popcorn-xp`** (subagent default), those team tool hooks are **not registered**; closeout is **`session close-check` / `session close`**, not **`TeamDelete`**. Scripts still **no-op** when no `.popcorn-xp/.active-team` exists. When **both** transports were bundled, subagent mode made team hooks no-op at runtime — prefer **one plugin** so only the intended hooks fire. `enforce-no-idle.sh` still runs **retro / shutdown / compaction** gates; in subagent mode, working-phase nudges skip context-store; **advisors** use task chat vs `.review-cursor-*`; **navigators** in `waiting_on_driver` must **cursor-ack** task chat (meta cursors). Agents with no `agent-state` registration (or empty role and phase) skip working nudges. **`SubagentStop`** runs `check-advice-on-subagent-stop.sh`. (**Codex:** **`Stop`** hook + cwd resolution are described in **`platforms/codex/subagent/skills/popcorn-xp/SKILL.md`**.)

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
- `session` — Thin wrapper that execs `shared/runtime/bin/session` (the canonical session helper)
- `.active-team` — Contains current team name (at `.popcorn-xp/.active-team`)
- `agent-state/*.json` — Per-agent machine-readable state (role, phase, task, write set)
- Signal files: `.retro-requested`, `.retro-{agent}.md`, `.shutdown`, `.checkpoint-cursor`

### Paired Task Model

Every logical task becomes two tasks: a drive task and a navigate task. This makes pairing structural — a drive task without a matching navigate task is a visible gap. The navigator stays active through the driver's full cycle and completes after verifying the driver's finished work. Rotation is encoded in the assignments: the T1 navigator claims T2's drive task, and vice versa.

### Advice Resolution Model

ADVICE.md is an append-only ledger. Hooks determine unresolved items by checking which IDs from `### TYPE ID — open` lines lack a matching `### ID — OUTCOME` resolution line. Resolution matching is case-insensitive. Valid outcomes: FIXED, REJECTED, INCORPORATED, NOTED.

### Agent Definitions

**Claude Code:** Agents in **`shared/agents/`** (symlinked under each Claude plugin) use Markdown with YAML frontmatter: `name`, `description`, `model`, `color`, `skills: [popcorn-xp-protocol]`, plus lens text. The `skills` field auto-loads the protocol into each agent's context.

**Codex:** Custom agents live under **`platforms/codex/subagent/agents/*.toml`** (`developer_instructions`, optional `[[skills.config]]`, etc.); generated install output may mirror them under **`.codex/agents/*.toml`**. See **`platforms/codex/subagent/README.md`** and **`research/official/codex/subagents.md`**.

### Shutdown Lifecycle (R4)

Four-phase lifecycle enforced by `enforce-no-idle.sh` reading signal files:

1. **Retro pending** (`.retro-requested`, no `.retro-{agent}.md`) — nudge retro submission (takes priority over shutdown so agents can write retros before being stopped)
2. **Shutdown** (`.shutdown` exists, retro done or never requested) — remind agent to approve shutdown_request from the lead (exit 2)
3. **Retro done** (both exist, no `.shutdown`) — allow idle, wait for shutdown
4. **Working** (default) — nudge agent to find work

## Official product snapshots (`research/official/`)

Frozen copies of **Claude Code** and **Codex** vendor documentation, checked into this repo for offline reference and diffing. **Not loaded at runtime.** Upstream may move or rename topics; treat these files as hints, not a live contract.

**Layout (paths from repo root):**

| Directory | Product | What to use it for |
|-----------|---------|-------------------|
| **`research/official/claude/`** | Claude Code | Plugin manifest shape, hook events and env, subagents, agent teams, tools |
| **`research/official/codex/`** | OpenAI Codex | Hook events and stdin/out, subagents, skills, `config.toml` keys |

**Files in `research/official/claude/`:** `plugin.md`, `hooks-ref.md`, `hooks-anthro.md`, `agents-anthro.md`, `skills-anthro.md`, `subagent.md`, `agent-teams-anthro.md`, `env.md`, `tools.md`.

**Files in `research/official/codex/`:** `hooks.md`, `subagents.md`, `skills.md`, `config.md`, `advanced-config.md`.

When you add or change hook scripts, compare event names, matchers, and payload fields against the matching **`hooks.md`** (and **`hooks-ref.md`** / **`hooks-anthro.md`** on the Claude side) before relying on behavior.

## Key Conventions

- Hook scripts and **`shared/runtime/bin/session`** use **`$CLAUDE_PROJECT_DIR`** when set (**Claude Code** sets it). **Codex** often leaves it unset; hook scripts and session then resolve the repo root with **`shared/runtime/lib/resolve-project-dir.sh`** from hook stdin **`cwd`** (or the shell cwd), then fall back to **`cwd`**. Keep **`.popcorn-xp/`** at the **git root** in normal layouts.
- `shared/runtime/bin/session` is the canonical session helper. A thin wrapper at `.popcorn-xp/{team}/session` execs it. Subagent mode adds `task-init`, `task-claim`, `task-release`, `task-complete`, `task-abandon`, `chat`, `chat-read`, `cursor-get`, `cursor-ack`, `health` (`--strict` optional), `close-check` (OBJECTIONs, locks, open task-bus claims, retro-or-handoff when `.retro-requested`, compaction handoffs), `close` (after `close-check`, requires `RETRO.md` with ≥5 lines; `close --force` skips `close-check` and `RETRO.md`; successful close removes `.popcorn-xp/.active-team` when it still names this team and truncates `.popcorn-xp/context-store.log`), and `mode`. **`session task {id}`** appends a placeholder task header; real driver/navigator names are written from **`task-claim`** / **`task-release`** (legacy extra args to `session task` are ignored). Most subcommands refuse to run if the team already has **`.closed.json`**. Optional: **`POPCORN_XP_EVENT_LOG_DEBUG`** — `events.jsonl` append failures print to stderr.
- `session log` advances the checkpoint cursor from `context-store.log` line count in **team** mode only; in **subagent** mode it only appends to LOG.md.
- Context store agent names follow `popcorn-xp:<agent-name>` convention (prefixed by hooks).
- `shared/skill-sources/templates.md` contains teammate prompt templates (driver, navigator, advisor) that the lead includes when spawning agents. This is the detailed version; `shared/skill-sources/core.md` is the transport-agnostic core and the protocol skill is the condensed version auto-loaded into agents.
