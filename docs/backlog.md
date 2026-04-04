# Popcorn XP Backlog

Living backlog for popcorn-xp improvements. Items are added from session retros and periodic audits.

## Legend

| Column | Values |
|--------|--------|
| Priority | Critical, High, Medium, Low |
| Fix type | Hook = shell script change, Protocol = SKILL.md / protocol text, Docs = architecture / CLAUDE.md, Config = agent frontmatter |
| Status | Open, Deferred, Done |

---

## Open

Nothing currently open. All known issues resolved through Session 5 (see Completed below).

---

## Deferred

Low-value items confirmed but not worth the implementation cost at this time.

| ID | Title | Priority | Fix type | Notes |
|----|-------|----------|----------|-------|
| V13 | Context store doesn't surface stale reads at rotation time | Medium | Hook + Protocol | Protocol already says "re-read files before driving"; mechanical hook adds complexity for marginal value. |
| R6 | Require explicit OBJECTION confirmation in task completion message | Medium | Hook + Protocol | `check-advice-on-complete.sh` catches the real problem; requiring text in completion messages is fragile. |
| V12 | `read_by` in context store only tracks last reader | Low | Hook | Log file has full history. Accept limitation or fix incidentally. |
| AA26 | `lockf` is macOS-only | Low | Hook | `context-store-update-read.sh` and `context-store-mark-dirty.sh` use `lockf`. No Linux target documented. |
| AA29 | `CLAUDE_CODE_COORDINATOR_MODE` undocumented | Low | Docs | Referenced in 7+ files, 0 in official Claude Code docs. Document as experimental in README/CLAUDE.md. |
| V31 | Session script bootstrapping gap | Low | Docs | Template changes don't propagate to running sessions. Inherent design limitation — document it. |
| AA23 | Lens text drift across source files | Low | Docs | Minor truncations between `agents/*.md` (canonical) and SKILL.md/architecture doc. Fix incidentally. |
| AA24 | `color: magenta` invalid + `color` not in frontmatter allowlist | Low | Config | `visual-designer.md` and `code-reviewer.md` both use `color: magenta`. Deferred unless runtime issues arise. |
| AA27 | Context store JSON example misleading in architecture doc | Low | Docs | Example shows `edited_by`/`edited_at` as always-present; only appear after edit. Fix incidentally. |
| H8 | Shell profile echo breaks JSON | Low | Docs | Docs-only item, no code change needed. |

---

## Completed

Full details are in git history. Grouped by session for traceability.

### Session 1 (2026-04-02) — 32 items

Core hook semantics, protocol scaffolding, session file conventions, shutdown lifecycle.

Key fixes: `systemMessage` → `additionalContext`; exit code semantics (exit 0 = allow, exit 2 = block); advice dual-write; `session` script; shutdown lifecycle (R4); context store hooks; protocol via `skills` field.

IDs: H1–H6, S1–S10, P1–P9, A1–A5, AT1–AT4, N1–N3, R1–R4.

### Session 2 (2026-04-02) — 3 items

Retro reliability and notification hooks.

Key fixes: retro-file enforcement on shutdown (R11). R5 and R10 re-opened as V9/V10 after discovering hooks never fired.

IDs: R5 (re-opened), R10 (re-opened), R11.

### Session 3 (2026-04-03) — 15 items

Shutdown deadlock, context store cleanup, protocol text updates, task claim enforcement.

Key fixes: shutdown deadlock (AA1); dead retro notification hooks removed (V9/V10); OBJECTION check at shutdown (V11); session script CWD fix (P13); context store metadata-only (V2); task claim hooks (V6/P12/P20); agent intent declaration (P14); post-compaction checklist (P15).

IDs: AA1, V2, V3, V4/AA15, V5, V6/P12/P20, V9/V10, V11, P13–P16, P19, AA4, AA9, AA13.

### Session 4 (2026-04-03) — 9 items

Navigator role effectiveness, agent phase state, integration test coverage, bugfix TDD lane.

Key fixes: explicit `agent-state/*.json` (P10/P11/P17); waiting-state-aware idle enforcement (V8); replay-fixture tests (P18); file ownership write sets (S3-1); READY artifact (S3-2); design alignment handshake (S3-3); bugfix lane exception (S4-3); compaction handoff hooks (S5-1).

IDs: P10/P11/P17, V8, P18, S3-1, S3-2, S3-3, S4-1, S4-2, S4-3, S5-1.

### Closed — Invalid/Already Fixed (2026-04-03) — 9 items

Items investigated and found non-issues or duplicates.

IDs: AA2, AA3, AA5, AA11, P20, R7, R8, R9, V12.
