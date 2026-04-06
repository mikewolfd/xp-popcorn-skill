---
name: popcorn-xp-protocol-core
description: Popcorn XP shared core for Codex — advice types, file boundaries, state, pairing intent. Use with popcorn-xp-protocol-subagent when runtime is subagent/file-bus. Does not cover SendMessage or Agent Teams (team transport lives in the Claude plugin skill).
---

# Popcorn XP — protocol core (transport-agnostic)

Load **`popcorn-xp-protocol-subagent`** next when `.popcorn-xp/{team}/.runtime-mode` is **`subagent`** (default on Codex). This vendored bundle includes **core + subagent** skills only; the Claude Code plugin’s full single-file teammate skill lives upstream (`skills/popcorn-xp-protocol/SKILL.md`) if you need **team**-transport text.

## Durable files (both modes)

- **`LOG.md`** — checkpoints and execution history (`session log`).
- **`ADVICE.md`** — typed **OBJECTION**, **SMELL**, **STEER**, **FYI** plus resolutions (`session advice`, `session resolve`). OBJECTIONs block task completion until engaged.
- **`RETRO.md`**, **`.retro-*`**, **`.shutdown`**, **handoff-*.md** — lifecycle (see main protocol skill).
- **`agent-state/{short-name}.json`** — role, phase, task (`session state`).
- Navigator **READY** artifacts: `navigator-ready-{agent}-T{n}.md` + `session ready`.

## Core behavior

1. One driver edits production code at a time; navigator and advisor do not edit unless they own an explicit drive task.
2. **Typed advice** belongs only in **ADVICE.md**; tactical chat is never the sole source of truth for blocking critique.
3. Advice is **input**, not orders — except **OBJECTION**, which must be resolved (fix or reject with reasoning) before **`session task-complete`** / completion gates.
4. Declare phase with **`session state`** so automation can reason about idle vs working.
5. Respect **write set** when assigned (`session writeset`).
6. **Git discipline:** check recent history on shared files before editing; commit before rotation when driving.

## Advice commands

```bash
.popcorn-xp/{team}/session advice TYPE ID [author] "summary"
.popcorn-xp/{team}/session resolve ID OUTCOME "detail"
```

Valid outcomes: **FIXED**, **REJECTED**, **INCORPORATED**, **NOTED** (case-insensitive in resolutions).

## When unsure

Re-read **`codex/skills/popcorn-xp-protocol-subagent/SKILL.md`** for task-bus commands, then **`codex/COMPANION.md`**. For the complete teammate protocol (including Claude **team** mode), open the **popcorn-xp** upstream repository’s **`skills/popcorn-xp-protocol/SKILL.md`** — not part of the minimal Codex vendor set.
