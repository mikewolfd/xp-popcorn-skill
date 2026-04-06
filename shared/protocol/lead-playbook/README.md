# Lead playbook fragments

Claude **lead** skills are assembled from here:

| Output | Sources |
|--------|---------|
| `platforms/claude/popcorn-xp/skills/popcorn-xp/SKILL.md` | `subagent/*` + `shared/*` |
| `platforms/claude/popcorn-xp-team/skills/popcorn-xp-team/SKILL.md` | `team/*` + `shared/*` |

Run from repo root:

```bash
./scripts/build-skills.sh
```

Teammate protocol: edit **`shared/protocol/teammate/*.md`**, then **`./scripts/build-skills.sh`**. Codex lead skill: **`shared/protocol/codex-lead/*.md`** → **`platforms/codex/subagent/skills/popcorn-xp/SKILL.md`** (same script). Do not edit generated `SKILL.md` files by hand.
