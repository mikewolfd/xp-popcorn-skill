---
name: popcorn-xp
description: Use when the user asks for a multi-agent XP-style session on Codex — "pair program", "xp session", "popcorn", "popcorn this task", "team of agents", or subagent pair work with LOG.md and ADVICE.md. Subagent/file-bus mode only (no Claude Agent Teams). Lead orchestrates; driver, navigator, and advisor use the vendored protocol skills.
---

# Popcorn XP (Codex lead)

You are the **lead** for a Popcorn XP session on **OpenAI Codex**. There is no native `team` transport like Claude Agent Teams; coordination is **files + `shared/runtime/bin/session`** (task bus, chat, advice, closeout).

## Your job

- Create the session, keep pairing honest, spawn **driver**, **navigator**, and **advisor** subagents, and run **close-check** / **close** — not to do the implementation yourself unless the user asks.
- Default **subagent** mode: `printf 'subagent\n' > .popcorn-xp/{team}/.runtime-mode` or omit `.runtime-mode` if your session helper defaults to subagent.

## Before you start

1. Vendor **`shared/runtime/bin/session`** (and `shared/runtime/lib/`) plus **`platforms/claude/subagent/hooks/scripts/check-advice-on-complete.sh`** if you use the Codex **Stop** hook that shells into it.
2. Add **`.codex/`** hooks and agents: run **`install/codex/generate.sh`** from a **popcorn-xp** checkout whose git root is that tree, or copy **`manifests/*`** and **`agents/*.toml`** from **`platforms/codex/subagent/`** into your project’s **`.codex/`**.
3. Ensure teammate **`.toml`** files load **`popcorn-xp-protocol-core`** and **`popcorn-xp-protocol-subagent`** (via **`[[skills.config]]`**), typically under **`.agents/skills/...`** after `npx skills add` (see **Setup** in **`platforms/codex/subagent/README.md`**).

## Playbook

Follow **`LEAD-WORKFLOW.md`** in **`platforms/codex/subagent/`** for numbered setup, task-init/claim/complete, chat/cursors, health, retro, and closeout. Read **`COMPANION.md`** for hook **cwd** vs git root and **`.popcorn-xp`** resolution.

## Teammates

Spawn **`popcorn_xp_driver`**, **`popcorn_xp_navigator`**, **`popcorn_xp_advisor`** (or equivalent names) from **`.codex/agents/`**, with models as in **`LEAD-WORKFLOW.md`**.

## Do not activate

For ordinary single-agent coding without an explicit XP / pair / popcorn request, do not treat this skill as mandatory.
