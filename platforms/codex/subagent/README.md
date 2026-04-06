# Popcorn XP — Codex integration

This directory is the canonical Codex source tree. Generate **`.codex/`** with **`./install/codex/generate.sh`** (repo root) for Codex discovery. Design notes live in [docs/architecture/dual-mode-codex-companion.md](../../../docs/architecture/dual-mode-codex-companion.md).

| Path | Role |
|------|------|
| `manifests/config.toml` | `codex_hooks = true`, `[agents]` limits |
| `manifests/hooks.json` | `SessionStart` + `Stop` → `hooks/*.sh` |
| `hooks/codex-session-start.sh` | Injects session reminder when `.popcorn-xp/.active-team` exists |
| `hooks/codex-stop-advice.sh` | OBJECTION gate via `platforms/claude/subagent/hooks/scripts/check-advice-on-complete.sh` |
| `skills/popcorn-xp-protocol-core/` | Shared core (advice, files, phases) |
| `skills/popcorn-xp-protocol-subagent/` | File-bus commands (`task-init`, `chat`, `close`, …) |
| `LEAD-WORKFLOW.md` | Vendored lead checklist (Codex / subagent) |
| `COMPANION.md` | Vendored hook + project-root notes |
| `agents/*.toml` | Short `developer_instructions` + `[[skills.config]]` |

**Consumer projects** should vendor **`shared/runtime/`**, **`platforms/claude/subagent/hooks/`** (for the advice gate), and this **`platforms/codex/subagent/`** tree. Run **`./install/codex/generate.sh`** (or copy `manifests/*` and `agents/*.toml` into **`.codex/`** yourself) when you need the consumer-facing Codex layout. Hooks resolve **`.popcorn-xp`** from **`git -C <hook-cwd> rev-parse --show-toplevel`** when **`CLAUDE_PROJECT_DIR`** is unset, so sessions may start in a **subdirectory** of the repo.

If **`[[skills.config]].path`** does not resolve relative to your project, set an **absolute** path to each skill directory (the folder containing `SKILL.md`).

**Tests:** `./tests/test-hooks.sh` (includes `CX-*` cases for these scripts).
