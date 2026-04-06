# Popcorn XP — Codex integration (reference layout)

This directory plus **`.codex/`** mirrors the layout described in [docs/dual-mode-codex-companion.md](../docs/dual-mode-codex-companion.md) (design notes in-repo; **self-contained** entrypoints below).

| Path | Role |
|------|------|
| `.codex/config.toml` | `codex_hooks = true`, `[agents]` limits |
| `.codex/hooks.json` | `SessionStart` + `Stop` → `codex/hooks/*.sh` |
| `codex/hooks/codex-session-start.sh` | Injects session reminder when `.popcorn-xp/.active-team` exists |
| `codex/hooks/codex-stop-advice.sh` | OBJECTION gate via `hooks/scripts/check-advice-on-complete.sh` |
| `codex/skills/popcorn-xp-protocol-core/` | Shared core (advice, files, phases) |
| `codex/skills/popcorn-xp-protocol-subagent/` | File-bus commands (`task-init`, `chat`, `close`, …) |
| `codex/LEAD-WORKFLOW.md` | Vendored lead checklist (Codex / subagent) |
| `codex/COMPANION.md` | Vendored hook + project-root notes |
| `.codex/agents/*.toml` | Short `developer_instructions` + `[[skills.config]]` |

**Consumer projects** should vendor **`bin/session`**, **`hooks/scripts/`** (including **`px-resolve-claude-project-dir.sh`**), this **`codex/`** tree, and **`.codex/`**. Hooks resolve **`.popcorn-xp`** from **`git -C <hook-cwd> rev-parse --show-toplevel`** when **`CLAUDE_PROJECT_DIR`** is unset, so sessions may start in a **subdirectory** of the repo.

If **`[[skills.config]].path`** does not resolve relative to your project, set an **absolute** path to each skill directory (the folder containing `SKILL.md`).

**Tests:** `./tests/test-hooks.sh` (includes `CX-*` cases for these scripts).
