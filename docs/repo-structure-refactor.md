# Repository Structure Refactor Proposal

This document proposes a clearer repository layout for Popcorn XP so contributors can quickly answer four questions:

1. What is shared product logic?
2. What is Claude-specific?
3. What is Claude team-mode specific?
4. What is Codex-specific?

The current repository mixes those concerns. Some folders are organized by artifact type (`agents/`, `skills/`, `hooks/`). Others are organized by host runtime (`.codex/`, `codex/`). The result is that the same concept appears in different places depending on which host consumes it.

## Problems in the Current Layout

- The real shared core is the shell/runtime layer in `bin/session` and `hooks/scripts/session-common.sh`, but it does not sit in a visibly shared location.
- Codex is split across hidden config in `.codex/` and visible source in `codex/`, so it is not obvious which side is authoritative.
- Claude subagent and Claude team-mode rules are mixed inside the same long lead and protocol skills.
- `agents/` contains shared personas, not host-specific agents, but the name is generic enough to look runtime-specific.
- The docs mix product shape, runtime transport, historical proposals, and vendored install notes in the same flat `docs/` directory.
- The repo still describes a `plugin.json`-style mental model in places even though the checked-in Claude marketplace artifact is `.claude-plugin/marketplace.json`.
- Tracked `.claude/projects/.../memory` files look like local workspace state, not product source.

## Refactor Goals

- Make one folder correspond to one ownership boundary.
- Put the shared product model above all host-specific adapters.
- Separate Claude subagent transport from Claude team transport.
- Treat hidden host folders as generated or mirrored install artifacts, not the primary source tree.
- Keep migration low-risk by preserving compatibility shims until docs, tests, and install paths catch up.

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
- Claude manifests or marketplace-facing packaging files

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

This contains Codex-specific packaging for the only supported Codex path:

- custom agent TOML files
- layered Codex skills
- Codex hook shims
- Codex config and install notes

The current split between `.codex/` and `codex/` should collapse into one visible source tree here. Hidden `.codex/` output can remain as a generated mirror for consumers that expect it. Discovery rules, path contracts, and install options are spelled out in [Codex integration: contracts, solutions, and unknowns](#codex-integration-contracts-solutions-and-unknowns).

### Hidden Directories

Hidden directories such as `.codex/` and `.claude-plugin/` should be treated as install artifacts, mirrors, or checked examples. They should not be the only source of truth for the product.

`.claude/projects/...` should not be versioned. That is local workspace memory, not reusable project source.

## Current-to-Target Mapping

| Current path | Target path | Reason |
|---|---|---|
| `bin/session` | `shared/runtime/bin/session` | Canonical shared runtime API |
| `hooks/scripts/session-common.sh` | `shared/runtime/lib/session-common.sh` | Shared shell library |
| `hooks/scripts/px-resolve-claude-project-dir.sh` | `shared/runtime/lib/resolve-project-dir.sh` | Shared path resolution, despite Claude-oriented name today |
| `agents/*.md` | `shared/personas/*.md` | Shared lenses, not host adapters |
| `references/protocol.md` | `shared/protocol/templates.md` | Long-form reference material |
| `skills/popcorn-xp-protocol/SKILL.md` | split across `shared/protocol/core.md` and Claude transport supplements | Separate philosophy from transport |
| `skills/popcorn-xp/SKILL.md` | Claude router plus per-mode lead docs under `platforms/claude/` | Reduce mixed runtime guidance |
| `hooks/hooks.json` | `platforms/claude/team/manifests/hooks.json` plus `platforms/claude/subagent/manifests/hooks.json` if needed | Make transport ownership explicit |
| `.codex/*` and `codex/*` | `platforms/codex/subagent/*` | One visible Codex source tree |
| `docs/*.md` | grouped under `docs/architecture/`, `docs/guides/`, `docs/archive/` | Separate active docs from history |

## Codex integration: contracts, solutions, and unknowns

Codex only discovers **`hooks.json` and `config.toml` next to active config layers** (for example repo `.codex/`). It does not read arbitrary paths such as `platforms/codex/subagent/manifests/` unless something copies, symlinks, or generates the standard layout. Phase 3 and `install/codex/` should name the chosen approach explicitly.

**Single `hooks.json` per config layer (constraint).** Unlike Claude, there is no second Codex “transport” to split manifests by. Codex merges hooks from multiple layers, but each layer still contributes one `hooks.json`. **Concrete:** keep one built artifact at `.codex/hooks.json` (or user merge); optionally maintain **source fragments** under `platforms/codex/subagent/hooks/` plus a small **build step** (shell/Make) that assembles or copies the final JSON. **Unknown:** whether the project wants fragment → merged JSON in-repo, or hand-maintained `.codex/hooks.json` with commands pointing at scripts under `platforms/codex/subagent/hooks/`.

**Hook command paths (concrete).** Today commands use `$(git rev-parse --show-toplevel)/codex/hooks/...`. After the move, point them at the new script root, for example `.../platforms/codex/subagent/hooks/...`, **or** keep a **repo-root symlink** `codex` → `platforms/codex/subagent` for a long transition so existing hook lines keep working.

**`[[skills.config]]` paths (concrete).** Agent TOMLs reference skill directories (e.g. `codex/skills/...`). Moving skills requires **updating every agent file** to the new relative (or absolute) paths, **or** keeping the `codex` symlink so `codex/skills/...` still resolves. **Unknown:** exact resolution rules for relative `path` across Codex CLI vs IDE vs future versions—**mitigation:** document that **vendored consumer copies** should use **absolute** paths when relative resolution breaks (already noted in `codex/README.md`).

**`.agents/skills` vs explicit `skills.config` (clarification).** Official Codex docs describe scanning `.agents/skills` from CWD upward. This repository primarily wires skills through **`[[skills.config]]` in agent TOMLs**. Moving trees under `platforms/codex/subagent/skills/` does **not** auto-register skills unless agents (or `.agents/skills` symlinks) are updated.

**Mirror / `install/` automation (concrete options).** Pick one primary approach and document it under `install/codex/`:

1. **Makefile (or script) target** — copy or rsync `platforms/codex/subagent/manifests/*` → `.codex/` and optionally sync agents into `.codex/agents/`.
2. **Symlink-based dev layout** — `.codex/agents` → `../platforms/codex/subagent/agents` (where tooling and OS policy allow).
3. **Generated + CI check** — treat `.codex/*` as build output; CI fails if it drifts from source.

**Unknown:** which option matches how most consumers vendor Popcorn XP (plain copy vs git submodule vs package); resolve when `install/codex/` is written.

**Plugins (unknown).** Future Codex **plugin** packaging may expect a different bundle shape than `platforms/codex/subagent/`. **Concrete later:** add a mapping table from platform source → plugin layout when packaging exists; until then, treat plugin layout as TBD.

## Suggested Documentation Shape

The docs should also separate by purpose:

- `docs/guides/`: how to install, run, and contribute
- `docs/architecture/`: active system design and folder ownership
- `docs/archive/`: historical proposals, session notes, and superseded alternatives

A good first pass:

- Move `architecture.md`, `dual-mode-proposal.md`, and this file into `docs/architecture/`
- Move `alt-proposal.md`, `hook-rationalization-proposal.md`, and `improvement-session-1.md` into `docs/archive/`
- Keep `backlog.md` at `docs/` or move it into `docs/guides/` depending on whether it is maintainer-only

## Migration Strategy

### Phase 1: Establish Shared Core

- Create `shared/runtime/`, `shared/protocol/`, and `shared/personas/`
- Move or copy the shared shell/runtime files first
- Leave wrappers in the current locations so tests and existing install instructions still work

### Phase 2: Split Claude by Transport

- Extract Claude subagent-specific guidance from the current lead and protocol skills
- Extract Claude team-specific guidance into a separate transport-specific layer
- Move team-only hooks under `platforms/claude/team/`
- Keep a thin top-level Claude entrypoint that routes to the correct mode

### Phase 3: Collapse Codex into One Source Tree

- Move `codex/` and `.codex/` **editable** source under `platforms/codex/subagent/` (agents, skills, hook scripts, manifest sources, Codex-oriented docs)
- Keep `.codex/` as the **consumer-facing** layout per Codex discovery rules: mirror, copy, or symlink per [Codex integration: contracts, solutions, and unknowns](#codex-integration-contracts-solutions-and-unknowns)
- Update **`.codex/hooks.json` command lines** and **every `[[skills.config]]` path** in agent TOMLs, **or** keep a repo-root **`codex` → `platforms/codex/subagent`** symlink until all references are migrated
- If using fragment manifests, add the **assembly step** (Make/script) and document it under `install/codex/`
- Keep Codex docs short and install-oriented; point design discussion back to shared architecture docs

### Phase 4: Clean Up Docs and Local Artifacts

- Group active docs by purpose
- Archive historical proposals
- Remove tracked `.claude/projects/...` memory files from version control
- Update the README to describe source-of-truth locations instead of the current mixed layout

### Phase 5: Remove Compatibility Shims

- Update tests and install paths to use the new locations
- Remove legacy wrappers only after all references are migrated

## Practical Rules for Future Additions

- Put shared semantics in `shared/`, even if Claude or Codex consumes them first.
- Put transport behavior where the verbs change.
- Do not let hidden host folders become the only authoritative location for editable source.
- Do not mix subagent and team transport instructions in the same long document when they use different primitives.
- Do not track local host memory or workspace residue in the repository.

## Recommendation

The simplest durable improvement is this:

1. Treat `shared/runtime/` as the product core.
2. Split `platforms/claude/subagent`, `platforms/claude/team`, and `platforms/codex/subagent`.
3. Treat `.codex/` and `.claude-plugin/` as install mirrors, not the architecture.

That structure matches how the system actually works today. The shared shell/runtime layer is already the stable core. The repository should make that obvious.
