---
name: popcorn-xp
description: Use when the user asks for a multi-agent XP-style session on Codex — "pair program", "xp session", "popcorn", "popcorn this task", "team of agents", or subagent pair work with LOG.md and ADVICE.md. Subagent/file-bus mode only (no Claude Agent Teams). Lead orchestrates; driver, navigator, and advisor use the vendored protocol skills.
---

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

## Teammate skills (load order)

| Need | Skill |
|------|--------|
| Shared rules (advice, files, phases) | **`popcorn-xp-protocol-core`** |
| Task bus, chat, cursors, closeout commands | **`popcorn-xp-protocol-subagent`** |

Wire via **`[[skills.config]]`** in **`agents/*.toml`** (typically under **`.agents/skills/...`** after `npx skills add`).

## Before you vendor

1. Plan to vendor **`shared/runtime/bin/session`** (and **`shared/runtime/lib/`**) plus **`platforms/claude/shared/hooks/scripts/advice/check-advice-on-complete.sh`** if you use the Codex **Stop** hook that shells into it.
2. Add **`.codex/`** hooks and agents: run **`install/codex/generate.sh`** from a **popcorn-xp** checkout whose git root is that tree, or copy **`manifests/*`** and **`agents/*.toml`** from **`platforms/codex/subagent/`** into your project’s **`.codex/`**.
3. Ensure teammate **`.toml`** files load **`popcorn-xp-protocol-core`** and **`popcorn-xp-protocol-subagent`** (see **Setup** in **`platforms/codex/subagent/README.md`**).

## 1. Session setup

1. Pick a short team name (e.g. `fix-auth`).
2. Create **`.popcorn-xp/{team}/`**, **`LOG.md`**, **`ADVICE.md`**, and a **`session`** wrapper that **`exec`**s your vendored **`shared/runtime/bin/session`**.
3. **`echo {team} > .popcorn-xp/.active-team`**
4. **`printf 'subagent\n' > .popcorn-xp/{team}/.runtime-mode`** (or omit **`.runtime-mode`** if **`shared/runtime/bin/session`** defaults to subagent).
5. Spawn **three** teammates (driver, navigator, advisor) with **`skills/...`** wired via **`[[skills.config]]`** in **`agents/*.toml`**.
6. Preferred Codex teammate defaults: `model="gpt-5.4-mini"` with `reasoning_effort="xhigh"` for normal pair work; escalate to `model="gpt-5.4"` with `reasoning_effort="medium"` when the slice is broader or repeated recovery suggests the cheaper path is false economy.

## 2. Tasks and pairing

- Each logical slice is a **pair**: **drive** + **navigate** task (navigator verifies after driver completes).
- **`session task-init {n}`** before work on task **n**.
- **`session task {n}`** for a **LOG.md** placeholder; real driver/navigator lines sync from **`task-claim`** / **`task-release`**.
- Claims: **`session task-claim`**, **`task-release`**, **`task-complete`**, **`task-abandon`** as in **`popcorn-xp-protocol-subagent`**.
- Typed advice only in **`ADVICE.md`** (**`session advice`** / **`session resolve`**). **OBJECTION** blocks completion until resolved.

## 3. Chat and cursors (subagent)

- Tactical: **`session chat`** / **`session chat-read`** on **`tasks/T{n}/back-forth.md`**.
- Navigators in **`waiting_on_driver`**: keep **`cursor-ack`** current.
- Advisors: **`session review`** to advance review cursors when required.

## 4. Health and closeout

- Run **`session health`** (or **`--strict`**) before risky handoffs.
- **`session retro-request`** → per-agent **`.retro-*.md`** or **`handoff-*.md`** as required.
- **`session close-check`** → append **`RETRO.md`** (≥5 real lines) → **`session close`** (or **`close --force`** only if you accept skipping gates). Successful **`close`** clears **`.popcorn-xp/.active-team`** (when it still names this team) and truncates **`context-store.log`**; run **`echo {team} > .popcorn-xp/.active-team`** again before the next slice. In each new **RETRO.md** entry, set **Lead host:** **`codex`** and **Task transport:** **`subagent`** (or **`team`** if you opted in) so future readers know which playbook and hooks applied — same fields as **`platforms/claude/popcorn-xp/skills/popcorn-xp/SKILL.md`** retro template.
- **Recovery:** After **two** failures on **session mechanics** for the **same drive seat** (claims, rotation, close-check), switch to a **bounded implementation worker** or a **fresh team** instead of retrying the same seat.

## 5. Claude plugin parity

The full Claude lead playbooks are **`platforms/claude/popcorn-xp/skills/popcorn-xp/SKILL.md`** (file-bus) and **`platforms/claude/popcorn-xp-team/skills/popcorn-xp-team/SKILL.md`** (Agent Teams) — not required on disk for this Codex-only bundle.

## Teammates

Spawn **`popcorn_xp_driver`**, **`popcorn_xp_navigator`**, **`popcorn_xp_advisor`** (or equivalent names) from **`.codex/agents/`**, with the model defaults in **§1** above.

## Do not activate

For ordinary single-agent coding without an explicit XP / pair / popcorn request, do not treat this skill as mandatory.
