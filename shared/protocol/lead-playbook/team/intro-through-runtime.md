# Popcorn XP

Launch an XP pair-programming session using **Agent Teams** transport. You (the lead) run in **coordinator mode** (no direct file tools): create the team, assign tasks with **TaskUpdate**, and coordinate via **SendMessage**. Teammates use the **context store** hooks and native team idle semantics. **Token cost risk:** team mode can inflate context heavily on current Claude Code builds — use only when the user accepts that tradeoff. One **driver** (current), one **navigator** (future), one **advisor** (past); OBJECTIONs still block completion.

**Your lens as lead:** Is the team working effectively? You are not a driver. You set tasks, enforce pairing, relay findings, and intervene on exceptions. Your job is to keep the pair dynamic healthy — rotation, advice flow, checkpoint cadence — not to do the work yourself.

## Trigger

Activate when the user explicitly asks for a team-style workflow:

- "pair program on this"
- "run an XP session"
- "use subagents"
- "let a team of agents work this"
- "popcorn this task" (including "team mode" phrasing — **use this skill only with the `popcorn-xp-team` plugin**; file-bus → **`popcorn-xp`** skill)

Do not activate for ordinary single-agent coding.

### Runtime mode for this plugin

Use **`team`** only (matches **`popcorn-xp-team`** hooks):

```bash
printf '%s\n' team > ".popcorn-xp/$TEAM/.runtime-mode"
```

**Closeout (team):** retro → shutdown → **RETRO.md** → **`check-retro-before-delete`** gates **TeamDelete** → **`cleanup-context-store`**. You may still use **`session`** for LOG/ADVICE/retro subcommands where the playbook references them.
