#!/usr/bin/env bash
# Regenerate Claude and Codex SKILL.md files from shared sources.
# - popcorn-xp-protocol: header + shared/skill-sources/teammate/*.md
# - popcorn-xp / popcorn-xp-team: fragments under shared/skill-sources/lead-playbook/
# - Codex lead popcorn-xp: fragments under shared/skill-sources/codex-lead/
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FRAG="$REPO_ROOT/shared/skill-sources/lead-playbook"
TM_FRAG="$REPO_ROOT/shared/skill-sources/teammate"
CX_LEAD="$REPO_ROOT/shared/skill-sources/codex-lead"
PROTO_OUT_SHARED="$REPO_ROOT/shared/skills/popcorn-xp-protocol/SKILL.md"
PROTO_OUT_TEAM="$REPO_ROOT/platforms/claude/popcorn-xp-team/skills/popcorn-xp-protocol/SKILL.md"
PROTO_OUT_CODEX_LEAD="$REPO_ROOT/platforms/codex/subagent/skills/popcorn-xp/SKILL.md"

subst_agents_pkg() {
  local pkg="$1"
  sed "s/__AGENTS_PKG__/${pkg}/g"
}

build_protocol_skill_shared() {
  local tmp
  tmp="$(mktemp)"
  {
    cat << 'EOF'
---
name: popcorn-xp-protocol
description: Popcorn XP pair-programming protocol — core rules, advice lifecycle, session file formats, and subagent transport for teammates in an XP session. Auto-loaded into popcorn-xp agents via the skills field. Native agents from other plugins should invoke this skill as their first action to load the protocol.
---

# Popcorn XP Protocol

**Popcorn-xp** agent definitions auto-load this skill via the `skills` field. **Native agents** from other plugins should invoke `Skill('popcorn-xp-protocol')` as their first action. **Codex** agents load the same skill via `[[skills.config]]`.

- **`shared/skill-sources/core.md`** — short transport-agnostic summary.
- **`shared/skill-sources/templates.md`** — long teammate prompt snippets for the lead.

The body below is the **teammate playbook** (built from fragments in **`shared/skill-sources/teammate/`**). It covers **core rules** and **subagent transport**. Agent Teams (**team**) transport is only in the `popcorn-xp-team` plugin variant.

EOF
    cat "$TM_FRAG/intro.md"
    printf '\n'
    cat "$TM_FRAG/common.md"
    printf '\n'
    cat "$TM_FRAG/subagent.md"
  } >"$tmp"
  mv "$tmp" "$PROTO_OUT_SHARED"
}

build_protocol_skill_team() {
  local tmp
  tmp="$(mktemp)"
  {
    cat << 'EOF'
---
name: popcorn-xp-protocol
description: Popcorn XP pair-programming protocol — core rules, advice lifecycle, session file formats, subagent and Agent Teams transports for teammates in an XP session. Auto-loaded into popcorn-xp agents via the skills field.
---

# Popcorn XP Protocol

**Popcorn-xp** agent definitions auto-load this skill via the `skills` field. **Native agents** from other plugins should invoke `Skill('popcorn-xp-protocol')` as their first action.

- **`shared/skill-sources/core.md`** — short transport-agnostic summary.
- **`shared/skill-sources/templates.md`** — long teammate prompt snippets for the lead.

The body below is the **teammate playbook** (built from fragments in **`shared/skill-sources/teammate/`**). This variant includes both **subagent** and **Agent Teams (team)** transports.

EOF
    cat "$TM_FRAG/intro.md"
    printf '\n'
    cat "$TM_FRAG/common.md"
    printf '\n'
    cat "$TM_FRAG/subagent.md"
    printf '\n'
    cat "$TM_FRAG/team.md"
  } >"$tmp"
  mv "$tmp" "$PROTO_OUT_TEAM"
}

build_codex_lead_skill() {
  local tmp
  tmp="$(mktemp)"
  {
    cat "$CX_LEAD/frontmatter.md"
    printf '\n'
    cat "$CX_LEAD/intro.md"
    printf '\n'
    cat "$CX_LEAD/workflow.md"
    printf '\n'
    cat "$CX_LEAD/footer.md"
  } >"$tmp"
  mv "$tmp" "$PROTO_OUT_CODEX_LEAD"
}

build_lead_subagent() {
  local out="$REPO_ROOT/platforms/claude/popcorn-xp/skills/popcorn-xp/SKILL.md"
  local pkg="popcorn-xp"
  local tmp
  tmp="$(mktemp)"
  {
    cat "$FRAG/subagent/frontmatter.md"
    printf '\n'
    cat "$FRAG/shared/prior-session.md"
    printf '\n'
    cat "$FRAG/subagent/intro-through-runtime.md"
    printf '\n'
    cat "$FRAG/subagent/subagent-essentials.md"
    printf '\n'
    cat "$FRAG/shared/role-roster.md" | subst_agents_pkg "$pkg"
    printf '\n'
    cat "$FRAG/shared/workflow-header.md"
    printf '\n'
    cat "$FRAG/shared/step-01-understand.md"
    printf '\n'
    cat "$FRAG/shared/step-02a.md"
    cat "$FRAG/shared/step-02-glob-block.md" | subst_agents_pkg "$pkg"
    cat "$FRAG/shared/step-02b.md"
    printf '\n'
    cat "$FRAG/subagent/step-02-tail.md" | subst_agents_pkg "$pkg"
    printf '\n'
    cat "$FRAG/shared/step-03a.md"
    printf '\n'
    cat "$FRAG/subagent/step-03-deps.md"
    printf '\n'
    cat "$FRAG/shared/step-03b.md"
    printf '\n'
    cat "$FRAG/shared/step-04a.md"
    printf '\n'
    cat "$FRAG/subagent/step-04-assign.md"
    printf '\n'
    cat "$FRAG/shared/step-04b.md"
    printf '\n'
    cat "$FRAG/subagent/step-05-monitor.md"
    printf '\n'
    cat "$FRAG/subagent/step-06-close.md"
    printf '\n'
    cat "$FRAG/shared/retro-format.md"
    printf '\n'
    cat "$FRAG/shared/footer.md"
  } >"$tmp"
  mv "$tmp" "$out"
}

build_lead_team() {
  local out="$REPO_ROOT/platforms/claude/popcorn-xp-team/skills/popcorn-xp-team/SKILL.md"
  local pkg="popcorn-xp-team"
  local tmp
  tmp="$(mktemp)"
  {
    cat "$FRAG/team/frontmatter.md"
    printf '\n'
    cat "$FRAG/shared/prior-session.md"
    printf '\n'
    cat "$FRAG/team/intro-through-runtime.md"
    printf '\n'
    cat "$FRAG/shared/role-roster.md" | subst_agents_pkg "$pkg"
    printf '\n'
    cat "$FRAG/shared/workflow-header.md"
    printf '\n'
    cat "$FRAG/shared/step-01-understand.md"
    printf '\n'
    cat "$FRAG/shared/step-02a.md"
    cat "$FRAG/shared/step-02-glob-block.md" | subst_agents_pkg "$pkg"
    cat "$FRAG/shared/step-02b.md"
    printf '\n'
    cat "$FRAG/team/step-02-tail.md" | subst_agents_pkg "$pkg"
    printf '\n'
    cat "$FRAG/shared/step-03a.md"
    printf '\n'
    cat "$FRAG/team/step-03-deps.md"
    printf '\n'
    cat "$FRAG/shared/step-03b.md"
    printf '\n'
    cat "$FRAG/shared/step-04a.md"
    printf '\n'
    cat "$FRAG/team/step-04-assign.md"
    printf '\n'
    cat "$FRAG/shared/step-04b.md"
    printf '\n'
    cat "$FRAG/team/step-05-monitor.md"
    printf '\n'
    cat "$FRAG/team/step-06-close.md"
    printf '\n'
    cat "$FRAG/shared/retro-format.md"
    printf '\n'
    cat "$FRAG/shared/footer.md"
  } >"$tmp"
  mv "$tmp" "$out"
}

build_protocol_skill_shared
build_protocol_skill_team
build_codex_lead_skill
build_lead_subagent
build_lead_team

echo "OK: $PROTO_OUT_SHARED"
echo "OK: $PROTO_OUT_TEAM"
echo "OK: $PROTO_OUT_CODEX_LEAD"
echo "OK: $REPO_ROOT/platforms/claude/popcorn-xp/skills/popcorn-xp/SKILL.md"
echo "OK: $REPO_ROOT/platforms/claude/popcorn-xp-team/skills/popcorn-xp-team/SKILL.md"
