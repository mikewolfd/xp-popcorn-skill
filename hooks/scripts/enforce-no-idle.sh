#!/bin/bash
set -euo pipefail

# enforce-no-idle.sh
# TeammateIdle hook: phase-aware idle enforcement.
#
# Phases (checked in priority order):
# 1. Retro pending: .retro-requested exists, .retro-{agent}.md missing → nudge retro
#    (takes priority over shutdown so agents can write retros before being stopped)
# 2. Shutdown: .shutdown exists → force-stop teammate
# 3. Retro done: .retro-requested + .retro-{agent}.md exist, no .shutdown → allow idle
# 4. Working: default → nudge "go find work"
#
# No-op when no active popcorn-xp session.

POPCORN_DIR="${CLAUDE_PROJECT_DIR:-.}/.popcorn-xp"
TEAM=$(cat "$POPCORN_DIR/.active-team" 2>/dev/null || true)
[ -z "$TEAM" ] && exit 0

TEAM_DIR="$POPCORN_DIR/$TEAM"
[ ! -d "$TEAM_DIR" ] && exit 0

# Read teammate_name from stdin (TeammateIdle input)
INPUT=$(cat)
AGENT=$(echo "$INPUT" | jq -r '.teammate_name // empty' 2>/dev/null || true)

# Phase 1: Retro pending — nudge retro before shutdown can take effect
if [ -f "$TEAM_DIR/.retro-requested" ] && [ -n "$AGENT" ] && [ ! -f "$TEAM_DIR/.retro-$AGENT.md" ]; then
  echo "Popcorn XP: Retro time. Submit your process observations now: .popcorn-xp/$TEAM/session retro $AGENT 'What worked? What didn't? What would you change about the process?'" >&2
  exit 2
fi

# Phase 2: Shutdown — force-stop (retro either done or never requested)
if [ -f "$TEAM_DIR/.shutdown" ]; then
  echo '{"continue": false, "stopReason": "Session complete — lead initiated shutdown"}'
  exit 0
fi

# Phase 3: Retro submitted, no shutdown yet — allow idle
if [ -f "$TEAM_DIR/.retro-requested" ]; then
  exit 0
fi

# Phase 4: Working — go find work
echo "Popcorn XP: Agents must never idle. If you're waiting, pick something productive: review the task description, read ahead in relevant files, check ADVICE.md for unresolved items, or investigate the next problem. Idle time is wasted pairing time." >&2
exit 2
