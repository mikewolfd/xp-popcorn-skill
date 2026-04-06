
Choose a short team name that reflects the task (e.g., `fix-parser`, `add-auth`, `refactor-api`).

```
TeamCreate "{team-name}"
```

Set up the session directory (replace `{team-name}` with your chosen name):

```bash
TEAM="{team-name}"
mkdir -p ".popcorn-xp/$TEAM"
echo "# Popcorn XP Log" > ".popcorn-xp/$TEAM/LOG.md"
printf "# Advice\n" > ".popcorn-xp/$TEAM/ADVICE.md"
printf '%s\n' team > ".popcorn-xp/$TEAM/.runtime-mode"
echo "$TEAM" > .popcorn-xp/.active-team
cat > ".popcorn-xp/$TEAM/session" << SCRIPT
#!/bin/bash
exec "$(git rev-parse --show-toplevel)/shared/runtime/bin/session" "\$@"
SCRIPT
chmod 555 ".popcorn-xp/$TEAM/session"
```

This creates `.popcorn-xp/{team-name}/` with fresh LOG.md, ADVICE.md, and a `session` helper that teammates use to append entries. RETRO.md is preserved across sessions.

**Identify verification commands.** Before spawning teammates, identify the project's verification commands (e.g., `tsc --noEmit`, `cargo check`, `ruff check .`, `make lint`) and include them in each teammate's task context. Agents must run these before marking any task complete.

**Set autocompact threshold.** Before spawning teammates, lower the auto-compaction threshold so agents compact before quality degrades:

```bash
export CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=70
```

**Pre-approve common operations.** Before spawning teammates, ensure your permission settings allow Read, Write, Edit, Bash, and Grep for the project directory without prompting. Teammates inherit the lead's permission settings — pre-approving reduces interruptions during pair work. Check `~/.claude/settings.json` or approve interactively during the first task.

