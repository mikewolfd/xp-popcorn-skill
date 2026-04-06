# Popcorn XP on Codex (vendored quick reference)

This file is part of the **self-contained Codex bundle** (`codex/` + `.codex/` + `bin/session` + `hooks/scripts/`). Long-form design history and Claude-vs-Codex comparisons live in the **popcorn-xp** source repository under `docs/dual-mode-codex-companion.md` if you have the full tree.

## Project root and hooks

Codex passes **`cwd`** in hook stdin; it may be a **subdirectory** of the repository. Popcorn hooks and **`bin/session`** resolve **`CLAUDE_PROJECT_DIR`** with **`git -C <cwd> rev-parse --show-toplevel`** when that variable is unset, then fall back to **`cwd`**. Keep **`.popcorn-xp/`** at the **git root** (normal layout).

`.codex/hooks.json` uses **`$(git rev-parse --show-toplevel)/codex/hooks/...`** so the shim path resolves; inside the shim, **`cwd`** still drives where the session thinks the project lives until the git step above corrects it.

## Transport

On Codex, use **`subagent`** mode only: **`bin/session`** task bus, **`tasks/T{n}/`**, **`ADVICE.md`**. There is no Codex-native Agent Teams **`SendMessage`** transport.

## Where to read next

| Need | File |
|------|------|
| Lead checklist | **`codex/LEAD-WORKFLOW.md`** |
| Shared rules (advice, files) | **`codex/skills/popcorn-xp-protocol-core/SKILL.md`** |
| Task bus commands | **`codex/skills/popcorn-xp-protocol-subagent/SKILL.md`** |
