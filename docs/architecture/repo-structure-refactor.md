# Repository Structure Refactor Proposal

**Status:** The cutover described below is **applied** in this repository (canonical trees under `shared/`, `platforms/*/subagent/`, grouped docs, `install/codex/generate.sh` for **`.codex/`**). This file remains as design history and rationale.

This document proposes a direct repository cutover for Popcorn XP so contributors can answer four questions without hunting through mixed folders:

1. What is shared product logic?
2. What is Claude-specific?
3. What is Claude team-mode specific?
4. What is Codex-specific?

The current repository mixes artifact type and runtime target. The same concept appears in several places depending on which host consumes it. That obscures ownership and invites duplicate sources.

## Problems in the Current Layout

- The shared runtime now lives in `shared/runtime/`, with the session helper at `shared/runtime/bin/session` and shell libraries under `shared/runtime/lib/`.
- Claude plugins live in `platforms/claude/popcorn-xp/`, `popcorn-xp-team/`, and `shared/`; Codex source lives in `platforms/codex/subagent/`.
- The mode-specific rules are split between the shared protocol core, the lead template docs, and the Claude/Codex source trees.
- The docs mix product shape, runtime transport, historical proposals, and install notes in one flat `docs/` directory.
- The checked-in Claude marketplace pointer is `.claude-plugin/marketplace.json`; there is no root `plugin.json` in this checkout.

## Refactor Goals

- Make one folder correspond to one ownership boundary.
- Put the shared product model above all host-specific adapters.
- Separate Claude subagent transport from Claude team transport.
- Treat hidden host folders as generated install artifacts, not source-of-truth trees.
- Cut over directly: move files once, update references, and delete the old locations. Do not preserve duplicate editable copies.

## Proposed Information Architecture

Use runtime target first, then artifact type.

```text
popcorn-xp/
├── shared/
│   ├── runtime/
│   │   ├── bin/
│   │   │   └── session
│   │   └── lib/
│   │       ├── session-common.sh
│   │       └── resolve-project-dir.sh
│   └── protocol/
│       ├── core.md
│       └── templates.md
├── platforms/
│   ├── claude/
│   │   └── subagent/
│   │       ├── agents/
│   │       ├── hooks/
│   │       └── skills/
│   └── codex/
│       └── subagent/
│           ├── agents/
│           ├── hooks/
│           ├── manifests/
│           └── skills/
├── docs/
├── research/
├── tests/
├── .claude-plugin/marketplace.json
├── .codex/
└── README.md / CLAUDE.md
```

## Ownership Rules

### `shared/`

This is the product core. Anything that defines Popcorn XP independent of host runtime belongs here:

- session file model
- advice semantics
- task-bus semantics
- state and closeout rules
- shared shell helpers
- shared protocol core and templates

If a file would still exist after removing all Claude- and Codex-specific packaging, it belongs in `shared/`.

### `platforms/claude/` (popcorn-xp, popcorn-xp-team, shared)

This contains the Claude source tree for the durable file-bus path:

- Claude lead skill for subagent mode
- Claude teammate protocol packaging
- Claude hooks and agents
- Marketplace-facing source that `.claude-plugin/marketplace.json` points at

Team-vs-subagent differences live in the skill docs and hook behavior, not in a second editable source tree.

This makes the highest-complexity runtime explicit instead of burying it inside mixed skills.

### `platforms/codex/subagent/`

This is the canonical Codex source tree:

- custom agent TOML files
- layered Codex skills
- Codex hook entrypoints
- Codex config and install notes
- Codex-oriented docs

`.codex/` is generated from this tree for Codex discovery. It should not be hand-edited source.

### Hidden Directories

Hidden directories such as `.codex/` and `.claude-plugin/` are generated install artifacts or published bundles. They are not the primary source of truth for the product.

## Current-to-Target Mapping

| Current path | Target path | Reason |
|---|---|---|
| `bin/session` | `shared/runtime/bin/session` | Canonical shared runtime API |
| `hooks/scripts/session-common.sh` | `shared/runtime/lib/session-common.sh` | Shared shell library |
| `hooks/scripts/px-resolve-claude-project-dir.sh` | `shared/runtime/lib/resolve-project-dir.sh` | Shared path resolution |
| `agents/*.md` | `shared/agents/*.md` | Claude teammate definitions |
| `references/protocol.md` | `shared/skill-sources/templates.md` | Long-form reference material |
| `skills/popcorn-xp-protocol/SKILL.md` | `shared/skill-sources/README.md`, `shared/skill-sources/templates.md`, `shared/skills/popcorn-xp-protocol/SKILL.md` | Separate shared rules from Claude packaging |
| `skills/popcorn-xp/SKILL.md` | `platforms/claude/popcorn-xp/skills/popcorn-xp/SKILL.md` | Lead workflow (file-bus) |
| `skills/popcorn-xp-team/SKILL.md` | `platforms/claude/popcorn-xp-team/skills/popcorn-xp-team/SKILL.md` | Lead workflow (Agent Teams) |
| `hooks/hooks.json` | `platforms/claude/popcorn-xp/hooks/hooks.json`, `popcorn-xp-team/hooks/hooks.json` | Claude lifecycle enforcement (split by transport) |
| `.codex/*` and `codex/*` | `platforms/codex/subagent/*` | One visible Codex source tree |
| `docs/*.md` | grouped under `docs/architecture/`, `docs/guides/`, `docs/archive/` | Separate active docs from history |

## Codex Integration

Codex still discovers `hooks.json` and `config.toml` from `.codex/`, so the repo needs an install step that materializes that layout from `platforms/codex/subagent/`. The canonical source stays in the visible tree; the generated `.codex/` output is only there because Codex expects it.

The direct rule is simple:

- Update `.codex/hooks.json` command lines to point at `platforms/codex/subagent/hooks/...`.
- Update every `[[skills.config]]` path in Codex agent TOMLs to point at `platforms/codex/subagent/skills/...`.
- Keep `.codex/` generated from the canonical tree, not maintained as a second source tree.
- Put any Codex-specific packaging or publishing logic in `install/codex/`.
- If future Codex plugin packaging needs a different bundle shape, map it from `platforms/codex/subagent/` rather than introducing another source root.

## Suggested Documentation Shape

The docs separate by purpose:

- `docs/guides/` — contributor lists (for example `backlog.md`)
- `docs/architecture/` — active system design, dual-mode proposals, this refactor note, Codex companion
- `docs/archive/` — historical proposals and session notes (`alt-proposal.md`, `hook-rationalization-proposal.md`, `improvement-session-1.md`)

**Applied layout:** `architecture.md`, `dual-mode-proposal.md`, `dual-mode-codex-companion.md`, and this file live under `docs/architecture/`; archive files under `docs/archive/`; `backlog.md` under `docs/guides/`. Interactive demo stays at `docs/demo/`.

## Migration Strategy

### Phase 1: Create the new canonical tree

- Create `shared/runtime/`, `shared/skill-sources/`, `platforms/claude/{popcorn-xp,popcorn-xp-team,shared}/`, and `platforms/codex/subagent/`
- Move the shared shell/runtime files and protocol docs into their final locations

### Phase 2: Update all references

- Update skills, agents, hooks, docs, tests, and install notes to the new paths
- Update Codex agent TOMLs to point directly at `platforms/codex/subagent/skills/...`
- Update Codex hook commands to point directly at `platforms/codex/subagent/hooks/...`

### Phase 3: Generate host layouts from source

- Generate `.codex/` from `platforms/codex/subagent/` for Codex runtime discovery — **`./install/codex/generate.sh`** (repo root)
- Generate any required Claude marketplace or install artifacts from the canonical tree

### Phase 4: Remove the old paths

- Delete `bin/session`, `hooks/scripts/session-common.sh`, `hooks/scripts/px-resolve-claude-project-dir.sh`, `agents/`, `codex/`, and `.codex/` source copies once the new tree is live
- Move the docs into their new folders
- Remove old references instead of keeping compatibility wrappers

## Practical Rules for Future Additions

- Put shared semantics in `shared/`, even if Claude or Codex consumes them first.
- Put transport behavior where the verbs change.
- Keep one editable source for each file.
- Do not let hidden host folders become the source of truth.
- Do not mix subagent and team transport instructions in the same long document when they use different primitives.
- Update references in the same change as the path move.

## Recommendation

The simplest durable improvement is direct:

1. Treat `shared/runtime/` as the product core.
2. Split Claude subagent, Claude team, and Codex subagent into `platforms/`.
3. Generate host-specific install layouts from the canonical tree.
4. Delete the old top-level locations after the reference updates land.

That structure makes ownership explicit and avoids building a compatibility layer that would outlive the migration.
