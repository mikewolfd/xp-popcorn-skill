## Lead Quality Bar

- **Session recovery.** Session files survive teammate loss. If the session is resumed after a crash or interruption, teammates no longer exist — spawn fresh agents seeded with LOG.md and ADVICE.md to reconstruct state. `/resume` and `/rewind` do not restore in-process teammates.
- **Research session calibration.** In research and analysis sessions (no code being written), expect fewer OBJECTIONs — correctness blockers are rare when the output is findings, not a diff. Peer DMs and SMELLs carry most of the coordination in these sessions. That's normal.
- **Stop spawning when done.** Stop spawning rounds when additional tasks stop changing the plan. Over-decomposing creates busywork.
- **Distinct lenses per seat.** Different roles must contribute materially different perspectives. Don't assign three agents with the same lens to different seats.

## Teammate protocol (do not duplicate here)

Typed **OBJECTION** / **SMELL** / **STEER** / **FYI** rules, **ADVICE.md** and **LOG.md** contracts, phase values, advice format, rotation, retro submission, and session file boundaries are defined in **`popcorn-xp-protocol`** (auto-loaded for popcorn-xp agents). The lead’s spawn prompts only need role assignment, names, and task context — plus **`shared/skill-sources/templates.md`** for long template text.

## Reference

Read **`shared/skill-sources/templates.md`** for teammate prompt templates and role blurbs. Include the relevant template sections in teammate prompts when spawning them.

## Other transport

- **File-bus / `session task-*`:** **`popcorn-xp`** plugin + **`popcorn-xp`** skill (sibling playbook under **`shared/skill-sources/lead-playbook/`**).
- **Agent Teams / `TaskUpdate` + `SendMessage`:** **`popcorn-xp-team`** plugin + **`popcorn-xp-team`** skill.
