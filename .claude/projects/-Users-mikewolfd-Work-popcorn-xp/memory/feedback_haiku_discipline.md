---
name: Haiku agents need strict constraints
description: Haiku-model agents create junk files, overwrite session scripts, resist shutdown, and write self-documentation instead of working. Opus/sonnet follow instructions precisely.
type: feedback
---

Haiku agents in popcorn-xp sessions create junk files (summaries, state files, ASCII art stats), overwrite the session helper script, resist shutdown (5+ attempts needed), and spend context writing self-documentation. Opus and sonnet agents follow instructions precisely.

**Why:** Observed in 2026-04-04 session with 12 agents. Every discipline problem (22 junk files, 3 session script overwrites, shutdown refusal) came from haiku agents. Opus experts and sonnet scouts were clean.

**How to apply:** When spawning haiku agents, add explicit constraints: "DO NOT create files in .popcorn-xp/. DO NOT write summary/checkpoint/state files. Only modify source code and append to LOG.md." Consider opus for all roles on critical sessions. Use maxTurns=60 on all haiku agents as the only reliable shutdown mechanism.
