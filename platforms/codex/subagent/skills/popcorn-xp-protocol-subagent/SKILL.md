---
name: popcorn-xp-protocol-subagent
description: Popcorn XP subagent/file-bus transport for Codex — task-init, task-claim, task chat, cursors, close-check, session health. Requires popcorn-xp-protocol-core. Use when .runtime-mode is subagent.
---

# Popcorn XP — subagent transport (Codex-aligned)

**Prerequisite:** `popcorn-xp-protocol-core`. Set once per session:

```bash
printf '%s\n' subagent > .popcorn-xp/{team}/.runtime-mode
```

## Task bus

```bash
./shared/runtime/bin/session task-init {n}
./shared/runtime/bin/session task {n}
./shared/runtime/bin/session task-claim {n} {your-short-name} driver|navigator|advisor [expected-revision]
./shared/runtime/bin/session task-revision {n}
./shared/runtime/bin/session task-release {n} {your-short-name}
./shared/runtime/bin/session task-complete {n} {your-short-name} {outcome} "note"
./shared/runtime/bin/session task-abandon {n} "reason"
./shared/runtime/bin/session task-advisor-scope {n} true|false
```

## Tactical chat (driver ↔ navigator ↔ advisor)

```bash
./shared/runtime/bin/session chat {n} {from} {kind} "message"
./shared/runtime/bin/session chat-read {n} [start-line]
./shared/runtime/bin/session cursor-get {your-short-name} {n}
./shared/runtime/bin/session cursor-ack {your-short-name} {n} {line}
```

`{line}` = last line fully processed in `tasks/T{n}/back-forth.md` (same line count as `wc -l`). Navigators in **`waiting_on_driver`** must stay current before idling. Advisors: run **`session review {your-short-name}`** after reading chat so review cursors stay aligned.

## Closeout

```bash
./shared/runtime/bin/session close-check
./shared/runtime/bin/session close
# Emergency skip (lead accepts risk):
./shared/runtime/bin/session close --force
```

Append **RETRO.md** (≥5 lines) before **`close`** when your process requires it. Include **Lead host:** (e.g. **`codex`**) and **Task transport:** **`subagent`** in the session header so accumulated retros stay attributable. **`close`** clears **`.popcorn-xp/.active-team`** (when it still names this team) and truncates **`context-store.log`**; set **`.active-team`** again for the next slice. **`events.jsonl`** records machine-facing audit events.

## Lead diagnostics

```bash
./shared/runtime/bin/session health
./shared/runtime/bin/session health --strict
```

## Wake-ups and stopping

The **lead** resumes or spawns workers; there is no native teammate mailbox. Codex **`Stop`** hooks in `manifests/hooks.json` can run the OBJECTION check via `hooks/codex-stop-advice.sh`.

## Reference

- `docs/architecture/dual-mode-codex-companion.md` — Codex vs Claude mapping.
- `docs/architecture/dual-mode-proposal.md` — full product shape.
- `shared/protocol/templates.md` — long teammate prompt templates.
