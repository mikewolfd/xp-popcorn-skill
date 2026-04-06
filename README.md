# Popcorn XP

Popcorn XP supports **extreme programming–style pair work** in multi-agent coding. One model covers three roles, session files, typed advice, and `bin/session`; **packaging changes per runtime**.

The repo ships a [Claude Code](https://claude.ai/code) plugin (`plugin.json`, `hooks/`, `skills/`, `agents/`) and an **OpenAI Codex** tree ([`.codex/`](./.codex/), [`codex/`](./codex/)). Hooks, skills, and notes match what each product exposes; see [codex/README.md](./codex/README.md) and [CLAUDE.md](./CLAUDE.md).

> [!WARNING]
> **Native `team` mode** (Claude Agent Teams and peer messaging) burns **very large** token budgets because of a **Claude Code bug**. Prefer **`subagent`** for daily work: leave `.runtime-mode` unset or set it to `subagent`, and coordinate with files and `bin/session`. Choose `team` only if you want live peer messaging and accept the cost.

**Defaults.** In subagent mode the lead keeps normal tools, spawns workers, and the room syncs through `.popcorn-xp/{team}/` and `ADVICE.md`. Team mode stays available for parity and for anyone who opts in after the warning.

**Codex.** Codex follows the **subagent** path only. We document no Codex-native `team` transport parallel to Claude Agent Teams.

---

## Overview

Start from the **popcorn-xp** skill (for example, “popcorn this task”). It creates a team directory, tasks, and teammates. The **driver** builds the current slice; the **navigator** reads ahead and raises risks and suggestions; the **advisor** checks outcomes, tests, and gaps. The driver and navigator **rotate** so pairing stays balanced; the advisor usually remains the standing reviewer unless you change that.

**Typed advice** lands in `ADVICE.md` with stable IDs. **OBJECTION** blocks clean completion until resolved; **SMELL**, **STEER**, and **FYI** nudge without the same hard block. Rules, IDs, and resolution wording sit in the protocol docs at the end of this file.

In **team** mode the lead runs coordinator-only and teammates use platform messaging. In **subagent** mode, treat “messaging” as **task chat plus shared files**. The diagram shows team wiring; on subagent defaults, substitute the file bus mentally.

```
You
 │
 ▼
Lead (Coordinator Mode)
 │  TeamCreate, TaskCreate, Agent, SendMessage, TaskStop — no filesystem tools
 │
 ├──► driver ◄──── SendMessage ────► navigator
 │
 └──► advisor
```

| Type        | Meaning              | Blocks completion? |
|-------------|----------------------|--------------------|
| OBJECTION   | “This is wrong”      | Yes                |
| SMELL       | “Looks off”          | No                 |
| STEER       | “Try another angle”  | No                 |
| FYI         | Context              | No                 |

---

## Session layout

Runtime files live under `.popcorn-xp/{team}/` (typically gitignored in consuming projects):

```
.popcorn-xp/{team}/
├── LOG.md           # Checkpoints and narrative
├── ADVICE.md        # Advice ledger + resolutions
├── RETRO.md         # Retrospectives
├── .runtime-mode    # subagent (default) or team
├── tasks/T{n}/      # Task bus (subagent mode)
└── session          # Wrapper around bin/session
```

Use `bin/session` for logs, advice, task claims, chat and cursors, health, closeout, and mode. For the full command list and behavior, read [CLAUDE.md](./CLAUDE.md).

---

## Why not a single orchestrator?

Many multi-agent setups route every decision through one hub. Popcorn XP keeps **peer coordination**: navigator and driver stay in touch **during** the work (team: platform messages; subagent: shared files and task chat), not only through a lead recap. Team mode drops file tools from the coordinator lead; subagent mode keeps the same habits with hooks and `bin/session` while the lead stays a normal coding agent.

---

## Hooks

`hooks/hooks.json` registers lifecycle and tool hooks. With no active session (no `.popcorn-xp/.active-team`), they no-op.

In **subagent** mode, scripts that exist only for Agent Teams transport—including context-store pairing with `TaskUpdate`—no-op. Idle, retro, shutdown, compaction, and subagent-stop checks still run where they apply.

| Hook area | Role (short) |
|-----------|----------------|
| TaskCompleted / SubagentStop | OBJECTION gate; reminders for other open advice |
| TeammateIdle | Idle nudges, checkpoints, shutdown lifecycle |
| Pre/Post Compact | Compaction handoff markers |
| PreToolUse Read/Edit | Soft-lock hints when another agent last edited a file (team path) |
| Pre/Post TaskUpdate | Task claims and `agent-state` sync (team path) |
| Pre/Post TeamDelete | Retro gate and context-store cleanup (team path) |

Append-only `.popcorn-xp/context-store.log` records who touched which paths and backs the soft-lock hints. It is not a merge lock. Per-event detail lives in [CLAUDE.md](./CLAUDE.md).

---

## Paired tasks

Split work into **pairs**: a drive task and a matching navigate task so the board shows pairing. Navigators stay with the driver through the cycle and finish when satisfied. The lead skill spells out assignments; see [references/protocol.md](./references/protocol.md).

---

## Agent personas

Teammates live under [`agents/`](./agents/) as Markdown with YAML frontmatter. Labels such as **scout**, **craftsman**, and **tester** name a *lens*, not a fixed seat—after rotation, any persona can drive or navigate.

---

## Setup (Claude Code)

Requires Claude Code **v2.1.32+**. For **team** mode with Agent Teams, use **Opus** where the platform requires it, and add to `~/.claude/settings.json`:

```json
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1",
    "CLAUDE_CODE_COORDINATOR_MODE": "1"
  }
}
```

Restart after saving. Subagent-default sessions need **not** run the lead coordinator-only.

Install the lead skill (examples):

```bash
npx skills add https://github.com/mikewolfd/xp-popcorn-skill --skill popcorn-xp
npx skills add /path/to/popcorn-xp --skill popcorn-xp   # local checkout
```

Teammates defined outside this plugin’s `agents/` still need **popcorn-xp-protocol** (see protocol docs). `tmux` or similar helps split panes; many setups run teammates in-process.

---

## Tests

```bash
./tests/test-hooks.sh
```

Bash 4+ only. Covers hook exit codes, advice gates, idle and shutdown behavior, context-store and task-claim paths where relevant, dual-mode (`DM-*`) cases, and Codex shims (`CX-*`). Failures print `FAIL:` with expected versus actual detail.

---

## Repository layout

```
popcorn-xp/
├── skills/popcorn-xp/            # Lead playbook
├── skills/popcorn-xp-protocol/   # Teammate protocol
├── agents/                       # Teammate definitions (Markdown)
├── bin/session                   # Session CLI
├── hooks/                        # hooks.json + scripts
├── references/protocol.md        # Long-form templates
├── research/official/claude/     # Claude product doc snapshots
├── research/official/codex/      # Codex product doc snapshots
├── .codex/ + codex/              # Codex plugin pack
├── tests/test-hooks.sh
├── plugin.json                   # Claude Code plugin manifest
├── CLAUDE.md                     # Maintainer-oriented detail (Codex-aware)
├── AGENT.md                      # Symlink → CLAUDE.md
└── README.md
```

Claude Code reads `plugin.json` for agents, skills, and hooks. Codex uses `.codex/` and `codex/` ([codex/README.md](./codex/README.md)). This tree is the full source. If you install only the lead skill tarball, add hooks and agents yourself.

---

## Limitations

- Agent Teams and coordinator behavior are **experimental** and may change.
- **Two surfaces** — Claude Code (`plugin.json` + hooks) and Codex (`.codex/` + `codex/`). Behavior tracks each platform’s APIs; [CLAUDE.md](./CLAUDE.md) notes the gaps.
- Several agents mean several contexts; **team** mode costs most until the upstream bug is fixed.
- Teammates do not share one model window. Put important facts in files or explicit messages.
- Team message history is capped; **LOG.md** and **ADVICE.md** persist.
- Keep session dirs under `.popcorn-xp/` out of git in real projects (see `.gitignore` here).

---

## Credits

Draws on Claude Code **Agent Teams** and **Coordinator Mode**, with a **subagent-first** path. Inspired by Extreme Programming pair practices.

---

## Troubleshooting

| Symptom | What to verify |
|---------|----------------|
| Hooks never run | `.popcorn-xp/.active-team` names a real team dir; project has plugin hooks enabled. |
| No context-store warnings | Subagent mode often disables those hooks by design. |
| Tasks won’t complete | Unresolved OBJECTION in `ADVICE.md` without a matching OUTCOME line. |
| Unexpected mode | Missing `.runtime-mode` means subagent; set `team` explicitly for Agent Teams. |
| Codex confusion | [codex/README.md](./codex/README.md) and [CLAUDE.md](./CLAUDE.md). |
| Lead still edits in “team” session | Coordinator mode off—set `CLAUDE_CODE_COORDINATOR_MODE=1` and restart. |
| Subagent teammate idle | `session state`, cursor and review flow per protocol; shutdown and retro signals. |

---

## Documentation

| Topic | Where |
|-------|--------|
| Lead workflow (spawn, tasks, shutdown) | [skills/popcorn-xp/SKILL.md](./skills/popcorn-xp/SKILL.md) |
| Teammate rules, advice format, task bus | [skills/popcorn-xp-protocol/SKILL.md](./skills/popcorn-xp-protocol/SKILL.md) |
| Long-form prompts and mode notes | [references/protocol.md](./references/protocol.md) |
| Dual mode, events, close semantics, Codex vs Claude | [CLAUDE.md](./CLAUDE.md), [codex/README.md](./codex/README.md) |
| Upstream product snapshots | [research/official/claude/](./research/official/claude/), [research/official/codex/](./research/official/codex/) |
| Hooks, context store, Claude vs Codex | [CLAUDE.md](./CLAUDE.md) |
