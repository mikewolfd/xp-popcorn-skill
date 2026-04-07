## Teammate protocol (do not duplicate here)

Typed **OBJECTION** / **SMELL** / **STEER** / **FYI** rules, **ADVICE.md** and **LOG.md** contracts, phase values, advice format, rotation, retro submission, and session file boundaries are defined in **`popcorn-xp-protocol`** (auto-loaded for popcorn-xp agents). The lead’s spawn prompts only need role assignment, names, and task context — plus **`shared/skill-sources/templates.md`** for long template text.

## Reference

Read **`shared/skill-sources/templates.md`** for teammate prompt templates and role blurbs. Include the relevant template sections in teammate prompts when spawning them.

## Other transport

- **File-bus / `session task-*`:** **`popcorn-xp`** plugin + **`popcorn-xp`** skill (sibling playbook under **`shared/skill-sources/lead-playbook/`**).
- **Agent Teams / `TaskUpdate` + `SendMessage`:** **`popcorn-xp-team`** plugin + **`popcorn-xp-team`** skill.
