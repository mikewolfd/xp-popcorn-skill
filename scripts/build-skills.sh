#!/usr/bin/env bash
# Regenerate Claude and Codex SKILL.md files from shared sources.
# - popcorn-xp-protocol: header + shared/protocol/teammate/*.md
# - popcorn-xp / popcorn-xp-team: fragments under shared/protocol/lead-playbook/
# - Codex lead popcorn-xp: fragments under shared/protocol/codex-lead/
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FRAG="$REPO_ROOT/shared/protocol/lead-playbook"
TM_FRAG="$REPO_ROOT/shared/protocol/teammate"
CX_LEAD="$REPO_ROOT/shared/protocol/codex-lead"
PROTO_OUT_CLAUDE="$REPO_ROOT/platforms/shared/skills/popcorn-xp-protocol/SKILL.md"
PROTO_OUT_CODEX_CORE="$REPO_ROOT/platforms/codex/subagent/skills/popcorn-xp-protocol-core/SKILL.md"
PROTO_OUT_CODEX_SUBAGENT="$REPO_ROOT/platforms/codex/subagent/skills/popcorn-xp-protocol-subagent/SKILL.md"
PROTO_OUT_CODEX_LEAD="$REPO_ROOT/platforms/codex/subagent/skills/popcorn-xp/SKILL.md"

subst_agents_pkg() {
  local pkg="$1"
  sed "s/__AGENTS_PKG__/${pkg}/g"
}

build_protocol_skill_claude() {
  local tmp
  tmp="$(mktemp)"
  {
    cat << 'EOF'
---
name: popcorn-xp-protocol
description: Popcorn XP pair-programming protocol — core rules, advice lifecycle, session file formats, and integration notes for teammates in an XP session. Auto-loaded into popcorn-xp agents via the skills field. Native agents from other plugins should invoke this skill as their first action to load the protocol.
---

# Popcorn XP Protocol

**Popcorn-xp** agent definitions auto-load this skill via the `skills` field. **Native agents** from other plugins should invoke `Skill('popcorn-xp-protocol')` as their first action.

- **`shared/protocol/core.md`** — short transport-agnostic summary.
- **`shared/protocol/templates.md`** — long teammate prompt snippets for the lead.

The body below is the **teammate playbook** (built from fragments in **`shared/protocol/teammate/`**).

EOF
    cat "$TM_FRAG/intro.md"
    printf '\n'
    cat "$TM_FRAG/common.md"
    printf '\n'
    cat "$TM_FRAG/subagent.md"
    printf '\n'
    cat "$TM_FRAG/team.md"
  } >"$tmp"
  mv "$tmp" "$PROTO_OUT_CLAUDE"
}

build_protocol_skill_codex_core() {
  local tmp
  tmp="$(mktemp)"
  {
    cat << 'EOF'
---
name: popcorn-xp-protocol-core
description: Popcorn XP shared core for Codex — advice types, file boundaries, state, pairing intent. Use with popcorn-xp-protocol-subagent when runtime is subagent/file-bus. Does not cover SendMessage or Agent Teams (team transport lives in the Claude plugin skill).
---

# Popcorn XP — protocol core (transport-agnostic)

Load **`popcorn-xp-protocol-subagent`** next when `.popcorn-xp/{team}/.runtime-mode` is **`subagent`** (default on Codex). This vendored bundle includes **core + subagent** skills only. Full teammate playbook (including Claude **team** mode) is built from **`shared/protocol/teammate/`** into **`platforms/shared/skills/popcorn-xp-protocol/SKILL.md`** in this repo — run **`scripts/build-skills.sh`** after edits.

EOF
    cat "$TM_FRAG/common.md"
  } >"$tmp"
  mv "$tmp" "$PROTO_OUT_CODEX_CORE"
}

build_protocol_skill_codex_subagent() {
  local tmp
  tmp="$(mktemp)"
  {
    cat << 'EOF'
---
name: popcorn-xp-protocol-subagent
description: Popcorn XP subagent/file-bus transport for Codex — task-init, task-claim, task chat, cursors, close-check, session health. Requires popcorn-xp-protocol-core. Use when .runtime-mode is subagent.
---

# Popcorn XP — subagent transport (Codex-aligned)

**Prerequisite:** `popcorn-xp-protocol-core`. Set once per session:

```bash
printf '%s\n' subagent > .popcorn-xp/{team}/.runtime-mode
```

EOF
    cat "$TM_FRAG/subagent.md"
    printf '\n'
    cat << 'EOF'
## Reference

- `docs/architecture/dual-mode-codex-companion.md` — Codex vs Claude mapping.
- `docs/architecture/dual-mode-proposal.md` — full product shape.
- `shared/protocol/templates.md` — long teammate prompt templates.
EOF
  } >"$tmp"
  mv "$tmp" "$PROTO_OUT_CODEX_SUBAGENT"
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

build_protocol_skill_claude
build_protocol_skill_codex_core
build_protocol_skill_codex_subagent
build_codex_lead_skill
build_lead_subagent
build_lead_team

echo "OK: $PROTO_OUT_CLAUDE"
echo "OK: $PROTO_OUT_CODEX_CORE"
echo "OK: $PROTO_OUT_CODEX_SUBAGENT"
echo "OK: $PROTO_OUT_CODEX_LEAD"
echo "OK: $REPO_ROOT/platforms/claude/popcorn-xp/skills/popcorn-xp/SKILL.md"
echo "OK: $REPO_ROOT/platforms/claude/popcorn-xp-team/skills/popcorn-xp-team/SKILL.md"
