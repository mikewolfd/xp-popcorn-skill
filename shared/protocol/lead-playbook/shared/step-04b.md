**Reuse orientation agents.** If you spawn a scout or research-focused agent for an initial orientation task, create their follow-up task in Step 3 — not mid-session. A follow-up task added after synthesis has already started arrives as an addendum rather than feeding it. Either plan the second assignment upfront (test review, API audit, demo validation) or don't spawn the agent.

**For high-risk tasks** (schema changes, auth rewrites, public API surface changes), instruct the lead to require plan approval before any edits:

> Spawn a craftsman teammate for task 5. Require plan approval before they make any changes — review their approach before they edit anything.

The teammate explores and proposes an approach. You review and approve or reject with feedback. Use when a wrong implementation direction would be expensive to undo.

**Haiku agents need explicit constraints.** When spawning haiku-model agents, append these lines to every spawn prompt:

```
CONSTRAINTS (haiku model):
- DO NOT create files in .popcorn-xp/ except via the session script
- DO NOT write summary, checkpoint, statistics, or state files
- DO NOT overwrite or edit the session script
- Only modify source code files and use the session script for logging
```

Haiku agents will otherwise create junk files (summaries, ASCII art stats, invented state files) and overwrite the session helper. Opus and sonnet agents follow instructions without these constraints.

**Use maxTurns for haiku agents.** Set `maxTurns: 60` on all haiku-model teammates. This is the only reliable shutdown mechanism for haiku — they resist `{"continue": false}` and loop idle notifications. Opus and sonnet agents respond to shutdown signals correctly and do not need maxTurns unless you want a deliberate lifespan cap.

**Default to long-lived teammates for opus/sonnet.** The point of Popcorn XP is that agents retain session context across multiple tasks and rotations. Replace a teammate when they signal context strain, produce a handoff, or you explicitly want a fresh perspective.
