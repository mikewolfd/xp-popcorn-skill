# Popcorn XP (Codex lead)

You are the **lead** for a Popcorn XP session on **OpenAI Codex**. There is no native `team` transport like Claude Agent Teams; coordination is **files + `shared/runtime/bin/session`** (task bus, chat, advice, closeout).

## Your job

- Create the session, keep pairing honest, spawn **driver**, **navigator**, and **advisor** subagents, and run **close-check** / **close** — not to do the implementation yourself unless the user asks.
- Default **subagent** mode: `printf 'subagent\n' > .popcorn-xp/{team}/.runtime-mode` or omit `.runtime-mode` if your session helper defaults to subagent.

## Project root, hooks, and transport

Codex passes **`cwd`** in hook stdin; it may be a **subdirectory** of the repository. Popcorn hooks and **`shared/runtime/bin/session`** resolve the project root with **`git -C <cwd> rev-parse --show-toplevel`** when **`CLAUDE_PROJECT_DIR`** is unset, then fall back to **`cwd`**. Keep **`.popcorn-xp/`** at the **git root** (normal layout).

**`platforms/codex/subagent/manifests/hooks.json`** uses **`$(git rev-parse --show-toplevel)/platforms/codex/subagent/hooks/...`** so hook paths resolve from any checkout root; inside the script, **`cwd`** still drives where the session thinks the project lives until the git step above corrects it.

On Codex, use **`subagent`** mode only: **`shared/runtime/bin/session`** task bus, **`tasks/T{n}/`**, **`ADVICE.md`**. There is no Codex-native Agent Teams **`SendMessage`** transport.

**`Stop`** (not Claude’s **`SubagentStop`**) runs the OBJECTION gate via **`platforms/codex/subagent/hooks/codex-stop-advice.sh`**, which shells into the shared **`check-advice-on-complete.sh`** when configured.

Long-form Claude vs Codex design notes: **`docs/architecture/dual-mode-codex-companion.md`** (full repo).

## Teammate skills

| Need | Skill |
|------|--------|
| Core rules + subagent transport | **`popcorn-xp-protocol`** |

Wire via **`[[skills.config]]`** in **`agents/*.toml`** (typically under **`.agents/skills/...`** after `npx skills add`). This is the same protocol used by Claude subagent mode — symlinked from `shared/skills/popcorn-xp-protocol/`.

## Before you vendor

1. Plan to vendor **`shared/runtime/bin/session`** (and **`shared/runtime/lib/`**) plus **`shared/hooks/scripts/advice/check-advice-on-complete.sh`** if you use the Codex **Stop** hook that shells into it.
2. Add **`.codex/`** hooks and agents: run **`install/codex/generate.sh`** from a **popcorn-xp** checkout whose git root is that tree, or copy **`manifests/*`** and **`agents/*.toml`** from **`platforms/codex/subagent/`** into your project’s **`.codex/`**.
3. Ensure teammate **`.toml`** files load **`popcorn-xp-protocol`** (see **Setup** in **`platforms/codex/subagent/README.md`**).
