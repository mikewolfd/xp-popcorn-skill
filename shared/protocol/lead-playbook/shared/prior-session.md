## Prior session context

!`[ -f .popcorn-xp/.active-team ] && TEAM=$(cat .popcorn-xp/.active-team) && echo "Active team: $TEAM" && tail -20 .popcorn-xp/$TEAM/LOG.md 2>/dev/null || echo "No active session."`
!`ls .popcorn-xp/*/RETRO.md 2>/dev/null | head -3 | xargs -I{} sh -c 'echo "=== {} ===" && tail -10 {}' || echo "No prior retros."`
