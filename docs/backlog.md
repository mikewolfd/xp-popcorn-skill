# Popcorn XP Backlog

Living backlog for popcorn-xp improvements. Items are added from session retros and periodic audits.

## Legend

| Column | Values |
|--------|--------|
| Priority | Critical, High, Medium, Low |
| Fix type | Hook = shell script change, Protocol = SKILL.md / protocol text, Docs = architecture / CLAUDE.md, Config = agent frontmatter, Test = test coverage |
| Status | Open, Deferred, Done |

---

## Open

No open items as of 2026-04-05.

---

## Deferred

Items confirmed but not worth the implementation cost. Validated 2026-04-05.

| ID | Title | Priority | Fix type | Notes |
|----|-------|----------|----------|-------|
| V51 | Enforce paired drive+navigate tasks | Medium | Hook | No system-to-session task ID mapping at hook time. Lead skill already enforces pairing structurally (SKILL.md Step 3). Hook can't query other tasks to verify a navigate task exists. |
| V53 | Block self-navigation on same work | Medium | Hook | Same blocker as V51. Can't correlate which drive/navigate tasks belong to the same logical work at hook time. |
| V44 | Consider BLOCKED advice type | Low | Protocol | No evidence of OBJECTION misuse for non-correctness blocks. OBJECTION covers "this is wrong"; forward-progress blocks go via SendMessage to lead. Revisit if misuse pattern emerges. |
| V13 | Context store doesn't surface stale reads at rotation time | Medium | Hook + Protocol | Protocol rule 16 explicitly covers this ("check before editing shared files"). No hookable rotation event exists. |
| AA24 | `color: magenta` invalid + `color` not in frontmatter allowlist | Low | Config | `visual-designer.md` and `code-reviewer.md` both use `color: magenta`. No runtime issues observed. |
| H8 | Shell profile echo breaks JSON | Low | Docs | Platform concern. Official Claude Code docs already cover mitigation. Low value to duplicate. |

---

## Completed

Full details are in git history. Grouped by session for traceability.

| Session | Date | Count | Theme | Key IDs |
|---------|------|-------|-------|---------|
| 1 | 2026-04-02 | 32 | Core hook semantics, protocol scaffolding, shutdown lifecycle | H1-H6, S1-S10, P1-P9, A1-A5, AT1-AT4, N1-N3, R1-R4 |
| 2 | 2026-04-02 | 3 | Retro reliability and notification hooks | R5, R10 (re-opened), R11 |
| 3 | 2026-04-03 | 15 | Shutdown deadlock, context store, task claim enforcement | AA1, V2-V6, V9-V11, P12-P20 |
| 4 | 2026-04-03 | 9 | Agent phase state, READY artifact, write sets, compaction | P10/P11/P17, V8, P18, S3-1-S5-1 |
| 5 | 2026-04-03 | 8 | Paired task model, session script extraction, hook rationalization | Per git (19e2627-0981351) |
| 6 | 2026-04-04 | 7 | CLI task timer tool (demo) | Per task-timer session log |
| 7 | 2026-04-04 | 10 | READY naming, task-correct, bench phase, shutdown terminal state | V32-V40 |
| 8 | 2026-04-04 | 9 | One-driver-at-a-time, rotation enforcement, path normalization | V45, V49-V58. V53 deferred |
| 9 | 2026-04-04 | 9 | Backlog sweep: dedup guards, write-set, TTL, status cmd, docs | V42, V59, V61, V62, V64, V65, V67, AA27 |
| 10 | 2026-04-04 | 3 | Code-review fixes: dedup anchoring, V61 conservative fallback, TTL tests | F1 (V61 malformed-date hard block), F2 (V64 anchor), F3 (V65 anchor) |
| 11 | 2026-04-04 | 7 | Backlog sweep: all open items cleared (hooks, protocol, docs) | V43, V46, V47, V68, V69, AA23, AA28 |
| 12 | 2026-04-04 | 4 | Navigator claims, fallback task anchors, advice ID validation, advisor loop | V70-V73 |
| 13 | 2026-04-04 | 11 | Backlog sweep: context-store.json elimination, advice extraction, simplification trio, role guard, advisor cursor, protocol canonicalization | V74-V84 |
| — | various | 17 | Closed — invalid, already fixed, or superseded | AA2, AA3, AA5, AA11, AA29, P20, R6, R7-R9, V12, V31, V41, V48, V63, V66 |
| 14 | 2026-04-05 | 3 | Backlog audit: closed V87 (already in protocol), V88/AA26 (lockf removed) | V87, V88, AA26 |
| 15 | 2026-04-05 | 9 | Backlog sweep: shutdown lifecycle, rotation guard, advice authorship, performance, docs cleanup | V85-V86, V89-V95 |

146 items completed + 17 closed across 15 sessions. 280 tests at last count.
