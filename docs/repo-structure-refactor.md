# Repository Structure Refactor Proposal

This document proposes a direct repository cutover for Popcorn XP so contributors can answer four questions without hunting through mixed folders:

1. What is shared product logic?
2. What is Claude-specific?
3. What is Claude team-mode specific?
4. What is Codex-specific?

The current repository mixes artifact type and runtime target. The same concept appears in several places depending on which host consumes it. That obscures ownership and invites duplicate sources.

## Problems in the Current Layout

- The shared runtime lives in `bin/session` and `hooks/scripts/session-common.sh`, but there is no visibly shared root.
- Codex is split between hidden config in `.codex/` and visible source in `codex/`.
- Claude subagent and Claude team-mode rules are mixed inside the same long lead and protocol skills.
- `agents/` contains shared personas, not host-specific agents, but the name reads like a runtime boundary.
- The docs mix product shape, runtime transport, historical proposals, and install notes in one flat `docs/` directory.
- The repo still uses a `plugin.json` mental model in places even though the checked-in Claude marketplace artifact is `.claude-plugin/marketplace.json`.

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
│   ├── protocol/
│   │   ├── core.md
│   │   └── templates.md
│   └── personas/
│       ├── craftsman.md
│       ├── expert.md
│       ├── tester.md
│       └── ...
├── platforms/
│   ├── claude/
│   │   ├── subagent/
│   │   │   ├── skills/
│   │   │   ├── hooks/
│   │   │   └── manifests/
│   │   └── team/
│   │       ├── skills/
│   │       ├── hooks/
│   │       └── manifests/
│   └── codex/
│       └── subagent/
│           ├── agents/
│           ├── skills/
│           ├── hooks/
│           └── manifests/
├── docs/
│   ├── architecture/
│   ├── guides/
│   └── archive/
├── tests/
│   ├── shared/
│   ├── claude/
│   └── codex/
└── install/
    ├── claude/
    └── codex/
```

## Ownership Rules

### `shared/`

This is the product core. Anything that defines Popcorn XP independent of host runtime belongs here:

- session file model
- advice semantics
- task-bus semantics
- state and closeout rules
- shared shell helpers
- shared teammate personas

If a file would still exist after removing all Claude- and Codex-specific packaging, it belongs in `shared/`.

### `platforms/claude/subagent/`

This contains Claude-specific packaging for the durable file-bus path:

- Claude lead skill for subagent mode
- Claude teammate protocol supplement for subagent transport
- Claude hooks that still apply in subagent mode
- Claude manifests and marketplace-facing packaging files

This folder should not contain team-only hook logic such as `TaskUpdate` claim enforcement or context-store behavior.

### `platforms/claude/team/`

This contains the live Agent Teams transport:

- team-mode lead skill
- team-mode protocol supplement
- `SendMessage`-based workflow rules
- context-store hooks
- `TaskUpdate` claim and sync hooks
- team shutdown and cleanup hooks

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
| `agents/*.md` | `shared/personas/*.md` | Shared lenses, not host adapters |
| `references/protocol.md` | `shared/protocol/templates.md` | Long-form reference material |
| `skills/popcorn-xp-protocol/SKILL.md` | split across `shared/protocol/core.md` and Claude transport supplements | Separate philosophy from transport |
| `skills/popcorn-xp/SKILL.md` | Claude router plus per-mode lead docs under `platforms/claude/` | Reduce mixed runtime guidance |
| `hooks/hooks.json` | `platforms/claude/team/manifests/hooks.json` and `platforms/claude/subagent/manifests/hooks.json` | Make transport ownership explicit |
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

The docs should separate by purpose:

- `docs/guides/`: how to install, run, and contribute
- `docs/architecture/`: active system design and folder ownership
- `docs/archive/`: historical proposals, session notes, and superseded alternatives

A good first pass:

- Move `architecture.md`, `dual-mode-proposal.md`, and this file into `docs/architecture/`
- Move `alt-proposal.md`, `hook-rationalization-proposal.md`, and `improvement-session-1.md` into `docs/archive/`
- Keep `backlog.md` at `docs/` or move it into `docs/guides/` depending on whether it is maintainer-only

## Migration Strategy

### Phase 1: Create the new canonical tree

- Create `shared/runtime/`, `shared/protocol/`, and `shared/personas/`
- Create `platforms/claude/subagent/`, `platforms/claude/team/`, and `platforms/codex/subagent/`
- Move the shared shell/runtime files and persona files into their final locations

### Phase 2: Update all references

- Update skills, agents, hooks, docs, tests, and install notes to the new paths
- Update Codex agent TOMLs to point directly at `platforms/codex/subagent/skills/...`
- Update Codex hook commands to point directly at `platforms/codex/subagent/hooks/...`

### Phase 3: Generate host layouts from source

- Generate `.codex/` from `platforms/codex/subagent/` for Codex runtime discovery
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
