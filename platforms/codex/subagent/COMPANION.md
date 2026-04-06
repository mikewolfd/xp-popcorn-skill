# Popcorn XP on Codex (vendored quick reference)

This file is part of the **Codex source tree** (`platforms/codex/subagent/` plus generated `.codex/`). Long-form design history and Claude-vs-Codex comparisons live in the **popcorn-xp** source repository under `docs/architecture/dual-mode-codex-companion.md` if you have the full tree.

## Project root and hooks

Codex passes **`cwd`** in hook stdin; it may be a **subdirectory** of the repository. Popcorn hooks and **`shared/runtime/bin/session`** resolve **`CLAUDE_PROJECT_DIR`** with **`git -C <cwd> rev-parse --show-toplevel`** when that variable is unset, then fall back to **`cwd`**. Keep **`.popcorn-xp/`** at the **git root** (normal layout).

`platforms/codex/subagent/manifests/hooks.json` uses **`$(git rev-parse --show-toplevel)/platforms/codex/subagent/hooks/...`** so the hook path resolves from any checkout root; inside the script, **`cwd`** still drives where the session thinks the project lives until the git step above corrects it.

## Transport

On Codex, use **`subagent`** mode only: **`shared/runtime/bin/session`** task bus, **`tasks/T{n}/`**, **`ADVICE.md`**. There is no Codex-native Agent Teams **`SendMessage`** transport.

## Where to read next

| Need | File |
|------|------|
| Lead checklist | **`LEAD-WORKFLOW.md`** |
| Shared rules (advice, files) | **`skills/popcorn-xp-protocol-core/SKILL.md`** |
| Task bus commands | **`skills/popcorn-xp-protocol-subagent/SKILL.md`** |
