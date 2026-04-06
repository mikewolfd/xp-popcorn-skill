# Popcorn XP

Launch an XP pair-programming session in **subagent / file-bus** mode. You (the lead) keep normal tools: spawn or resume subagents, drive the **task bus** (`session task-*`, `chat`, cursors), and enforce pairing. Teammates coordinate through **durable files**, not `TaskUpdate` or peer `SendMessage`. One **driver** (current), one **navigator** (future), one **advisor** (past); driver and navigator rotate; OBJECTIONs still block completion.

**Your lens as lead:** Is the team working effectively? You are not a driver. You set tasks, enforce pairing, relay findings, and intervene on exceptions. Your job is to keep the pair dynamic healthy — rotation, advice flow, checkpoint cadence — not to do the work yourself.

## Trigger

Activate when the user explicitly asks for a team-style workflow:

- "pair program on this"
- "run an XP session"
- "use subagents"
- "let a team of agents work this"
- "popcorn this task" (including "subagent mode" / "team mode" phrasing — **use this skill only with the `popcorn-xp` plugin**; Agent Teams → **`popcorn-xp-team`** skill)

Do not activate for ordinary single-agent coding.

### Runtime mode for this plugin

**`subagent`** only (default if `.runtime-mode` is missing):

```bash
printf '%s\n' subagent > ".popcorn-xp/$TEAM/.runtime-mode"
```

Or: `.popcorn-xp/$TEAM/session mode subagent`.

**Subagent mode essentials:**
