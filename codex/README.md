# Popcorn XP — Codex integration (reference layout)

This directory plus **`.codex/`** implements [docs/dual-mode-codex-companion.md](../docs/dual-mode-codex-companion.md): hooks, layered skills, and example agents.

| Path | Role |
|------|------|
| `.codex/config.toml` | `codex_hooks = true`, `[agents]` limits |
| `.codex/hooks.json` | `SessionStart` + `Stop` → `codex/hooks/*.sh` |
| `codex/hooks/codex-session-start.sh` | Injects session reminder when `.popcorn-xp/.active-team` exists |
| `codex/hooks/codex-stop-advice.sh` | OBJECTION gate via `hooks/scripts/check-advice-on-complete.sh` |
| `codex/skills/popcorn-xp-protocol-core/` | Shared core (advice, files, phases) |
| `codex/skills/popcorn-xp-protocol-subagent/` | File-bus commands (`task-init`, `chat`, `close`, …) |
| `.codex/agents/*.toml` | Short `developer_instructions` + `[[skills.config]]` |

**Consumer projects** should vendor `bin/session`, `hooks/scripts/`, and this `codex/` + `.codex/` tree (or symlink). Hooks assume **`git rev-parse --show-toplevel`** resolves to the repo that contains `hooks/scripts/` and `codex/hooks/`.

If **`[[skills.config]].path`** does not resolve relative to your project, set an **absolute** path to each skill directory (the folder containing `SKILL.md`).

**Tests:** `./tests/test-hooks.sh` (includes `CX-*` cases for these scripts).
