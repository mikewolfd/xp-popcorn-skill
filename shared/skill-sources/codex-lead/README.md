# Codex lead skill (sources)

Edit these fragments, then run **`./scripts/build-skills.sh`** from the repo root.

Output: **`platforms/codex/subagent/skills/popcorn-xp/SKILL.md`** (consumed by `npx skills add …/platforms/codex/subagent`).

| Fragment | Role |
|----------|------|
| `frontmatter.md` | YAML `name` + `description` |
| `intro.md` | Title, job, hooks/transport, teammate skills table, vendor steps |
| `workflow.md` | §1–§5 session through Claude parity |
| `footer.md` | Teammates spawn, do-not-activate |
