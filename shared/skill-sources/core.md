# Popcorn XP Shared Core

This file is a **short** transport-agnostic summary. The **full teammate playbook**
that ships in skills lives under **`shared/skill-sources/teammate/*.md`**. The **Codex lead**
skill is built from **`shared/skill-sources/codex-lead/*.md`**. Run **`./scripts/build-skills.sh`**
to regenerate vendored **`SKILL.md`** files (Claude + Codex).

## Seats

- Driver: current work, owns the active implementation task, and is the only
  seat that edits code.
- Navigator: future work, reads ahead, and raises typed advice.
- Advisor: past work, reviews checkpoints and merged changes.

Seats rotate by task. The product model stays the same even when the transport
changes.

## Durable files

- `LOG.md` records checkpoints and the work history.
- `ADVICE.md` records typed advice and its resolutions.
- `RETRO.md` records end-of-session retrospectives.
- `agent-state/*.json` records the current seat state for each agent.
- `tasks/T{n}/` stores task-bus chat and metadata when the runtime uses the
  file-backed subagent flow.

## Advice

Advice is input, not instruction. The type determines the weight:

- `OBJECTION` means the claim is factually wrong until resolved.
- `SMELL` means the claim looks off and should be considered.
- `STEER` means there is a different approach worth evaluating.
- `FYI` means there is context worth noting.

Only OBJECTION blocks completion. The other types are reminders.

## Session discipline

- Declare role and phase explicitly in session state.
- Keep the active write set small and do not edit outside it without
  reassignment.
- Log checkpoints as the work happens, not after the fact.
- Check recent history before editing shared files.
- Finish with a clean closeout, including the required retrospective.

## Canonical helpers

- `shared/runtime/bin/session` is the session helper used by both product
  surfaces.
- `shared/runtime/lib/session-common.sh` and
  `shared/runtime/lib/resolve-project-dir.sh` are the shared shell helpers.
