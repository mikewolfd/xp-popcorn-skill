---
name: install
description: "Configure Claude Code settings for Popcorn XP. Sets required environment variables (CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS, CLAUDE_CODE_COORDINATOR_MODE) in the user's ~/.claude/settings.json."
triggers:
  - "install popcorn"
  - "setup popcorn"
  - "configure popcorn"
  - "enable agent teams"
---

# Popcorn XP Install

Configure Claude Code for Popcorn XP pair programming sessions.

## Required Environment Variables

Popcorn XP needs two env vars in `~/.claude/settings.json`:

| Variable | Value | Purpose |
|----------|-------|---------|
| `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` | `"1"` | Enables Agent Teams (peer-to-peer messaging, TeamCreate/TeamDelete) |
| `CLAUDE_CODE_COORDINATOR_MODE` | `"1"` | Forces the lead into coordinator mode (no file tools) |

## Instructions

1. Read `~/.claude/settings.json`
2. Check if both env vars already exist in the `env` object
3. If both are already set, tell the user they're good to go
4. If missing, merge them into the existing `env` object (preserve all existing keys)
5. Write the updated file using Edit (not Write, to avoid clobbering)
6. Confirm what was added

### Merge rules

- If `env` key exists, add the missing vars alongside existing entries
- If `env` key does not exist, create it with both vars
- Never remove or modify existing env vars
- Never touch other top-level keys (permissions, hooks, plugins, etc.)

### After configuring

Tell the user:
- Restart Claude Code for the env vars to take effect
- They can now use `/popcorn-xp` or say "popcorn this task" to start a session
- Opus 4.6 model is required for Agent Teams
