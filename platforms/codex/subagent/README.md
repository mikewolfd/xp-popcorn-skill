# Popcorn XP — Codex integration

This directory is the canonical Codex source tree. Install **skills** into your project with the [open agent skills CLI](https://github.com/vercel-labs/skills) (`npx skills`), then generate **`.codex/`** for hooks and agents.

## Install with `npx skills`

From the **consumer project root** (where you want **`.agents/skills/`**):

```bash
# Local checkout of popcorn-xp
npx skills add /path/to/popcorn-xp/platforms/codex/subagent --agent codex --skill '*' --yes

# Or from Git (use your fork URL and branch)
npx skills add https://github.com/mikewolfd/xp-popcorn-skill/tree/master/platforms/codex/subagent --agent codex --skill '*' --yes
```

That installs **`popcorn-xp`** (lead), **`popcorn-xp-protocol-core`**, and **`popcorn-xp-protocol-subagent`** under **`.agents/skills/`**, matching **`[[skills.config]]`** paths in **`.codex/agents/*.toml`**.

Then add **`.codex/`** hooks and agent definitions:

- **Same git root as this tree:** run **`./install/codex/generate.sh`** from the popcorn-xp repo root.
- **Another repository:** copy **`manifests/*`** and **`agents/*.toml`** from this directory into that project’s **`.codex/`**.

Design notes: [docs/architecture/dual-mode-codex-companion.md](../../../docs/architecture/dual-mode-codex-companion.md).

| Path | Role |
|------|------|
| `manifests/config.toml` | `codex_hooks = true`, `[agents]` limits |
| `manifests/hooks.json` | `SessionStart` + `Stop` → `hooks/*.sh` |
| `hooks/codex-session-start.sh` | Injects session reminder when `.popcorn-xp/.active-team` exists |
| `hooks/codex-stop-advice.sh` | OBJECTION gate via `platforms/shared/hooks/scripts/advice/check-advice-on-complete.sh` |
| `skills/popcorn-xp/` | Lead skill (`npx skills` / **`.agents/skills/popcorn-xp`**) |
| `skills/popcorn-xp-protocol-core/` | Shared core (advice, files, phases) |
| `skills/popcorn-xp-protocol-subagent/` | File-bus commands (`task-init`, `chat`, `close`, …) |
| `skills/popcorn-xp/SKILL.md` | Codex lead playbook (**built** from **`shared/protocol/codex-lead/*.md`**) |
| `agents/*.toml` | Short `developer_instructions` + `[[skills.config]]` |

**Consumer projects** should vendor **`shared/runtime/`**, **`platforms/shared/hooks/scripts/`** (for the advice gate), and this **`platforms/codex/subagent/`** tree. Use **`npx skills add …/platforms/codex/subagent --agent codex`** for skills, then **`generate.sh`** or a manual copy into **`.codex/`** as above. Hooks resolve **`.popcorn-xp`** from **`git -C <hook-cwd> rev-parse --show-toplevel`** when **`CLAUDE_PROJECT_DIR`** is unset, so sessions may start in a **subdirectory** of the repo.

If you **vendor this tree without `npx skills`**, change **`[[skills.config]].path`** in **`agents/*.toml`** to **`platforms/codex/subagent/skills/<skill-name>`** (repo-root-relative), or set **absolute** paths to each folder that contains **`SKILL.md`**.

**Tests:** `./tests/test-hooks.sh` (includes `CX-*` cases for these scripts).
