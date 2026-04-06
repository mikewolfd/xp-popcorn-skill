# Shared hook scripts

Bash hooks for both Claude plugins (`popcorn-xp`, `popcorn-xp-team`). Plugin `hooks/hooks.json` entries point here via `${CLAUDE_PLUGIN_ROOT}/hooks/scripts/...` (symlinked `hooks/scripts` → `shared/hooks/scripts`).

| Directory | Contents |
|-----------|----------|
| **`advice/`** | `check-advice-on-complete.sh` (TaskCompleted / session gate), `check-advice-on-subagent-stop.sh` |
| **`team/`** | Agent Teams transport: `TaskUpdate` / context-store / `TeamDelete` hooks + `context-store-log.sh` (sourced by team hooks and by `lifecycle/enforce-no-idle.sh` for team-mode checkpoint logic) |
| **`lifecycle/`** | `enforce-no-idle.sh`, `mark-compact-pending.sh`, `record-compact-summary.sh` |

`REPO_ROOT` in each script is six levels up from the script file (`…/platforms/claude/shared/hooks/scripts/<dir>/file.sh` → repo root).
