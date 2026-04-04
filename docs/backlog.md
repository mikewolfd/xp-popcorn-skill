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

### bin/session bugs

Small, self-contained fixes in `bin/session`. All follow the existing dedup pattern (`grep -qF` guard).

| ID | Priority | Title | Proposed fix |
|----|----------|-------|-------------|
| ~~V64~~ | ~~Low~~ | ~~Duplicate `## Task` headers in LOG.md~~ | ~~Done.~~ `grep -qF "## Task $ID"` dedup guard added to `session task`. |
| ~~V65~~ | ~~Low~~ | ~~Duplicate READY artifacts in LOG.md~~ | ~~Done.~~ LOG.md append in `session ready` guarded with `grep -qF "@$AGENT task $TASK_ID"`. |
| ~~V67~~ | ~~Low~~ | ~~Write set not cleared on role change~~ | ~~Done.~~ `session state` clears `write_set` on role mismatch; `update-task-state.sh` clears on completion. |

### Hook enforcement gaps

| ID | Priority | Title | Proposed fix |
|----|----------|-------|-------------|
| ~~V61~~ | ~~Medium~~ | ~~Crashed agent blocks all edits (V50 stale-state)~~ | ~~Done.~~ TTL check (10 min) added to one-driver-at-a-time guard in `context-store-mark-dirty.sh`. Stale state downgrades hard block to `additionalContext` warning. |
| ~~V68~~ | ~~Low~~ | ~~State created for non-team agents~~ | ~~Done.~~ Guard in `update-task-state.sh` skips agents without pre-existing state files. |

### Observability

| ID | Priority | Title | Proposed fix |
|----|----------|-------|-------------|
| ~~V59~~ | ~~Medium~~ | ~~Add `session status` subcommand~~ | ~~Done.~~ `session status` prints a table of agent/role/phase/task/updated_at from `agent-state/*.json`. |
| ~~V42~~ | ~~Low~~ | ~~Soft-lock warning visibility~~ | ~~Done.~~ Soft lock message now prefixed with `⚠ SOFT LOCK:`. |

### Protocol / workflow

| ID | Priority | Title | Proposed fix |
|----|----------|-------|-------------|
| ~~V43~~ | ~~Low~~ | ~~Accept retro via SendMessage~~ | ~~Done.~~ Fallback path added to lead skill Step 6 shutdown workflow. |
| ~~V46~~ | ~~Low~~ | ~~Phantom task — driver completes but status not updated~~ | ~~Done.~~ Rule 15 added to protocol skill: TaskUpdate(completed) required after tests pass. |
| ~~V47~~ | ~~Low~~ | ~~Task assignment message ordering~~ | ~~Done.~~ Monitor section instruction: wait for TaskUpdate confirmation before assigning next. |

### Path handling

| ID | Priority | Title | Proposed fix |
|----|----------|-------|-------------|
| ~~V60~~ | ~~Low~~ | ~~`./` not normalized in px_normalize_path~~ | ~~Done (uncommitted).~~ `p="${p#./}"` added to `px_normalize_path` in session-common.sh. Commit with next batch. |

### Docs

| ID | Priority | Title | Proposed fix |
|----|----------|-------|-------------|
| ~~AA23~~ | ~~Low~~ | ~~Lens text drift across source files~~ | ~~Done.~~ All 9 lenses synced across agents/*.md, docs/architecture.md, and skills/popcorn-xp/SKILL.md. Verified by opus code review. |
| ~~AA27~~ | ~~Low~~ | ~~Context store JSON example stale in architecture doc~~ | ~~Done.~~ Removed PostToolUse Read entry and `context-store-update-read.sh` reference. Updated JSON example to `{dirty, edited_by, edited_at}` only. |
| ~~AA28~~ | ~~Low~~ | ~~Architecture doc lists deleted hooks as registered~~ | ~~Done.~~ 4 stale hook rows removed, SubagentStop section removed, phase count corrected to Seven. |

### Testing

| ID | Priority | Title | Proposed fix |
|----|----------|-------|-------------|
| ~~V62~~ | ~~Low~~ | ~~V52 task-correct + rotation guard interaction~~ | ~~Done.~~ Two-case test added: corrected-out agent allowed, corrected-to agent blocked. |

### Hook enforcement gaps (new)

| ID | Priority | Title | Proposed fix |
|----|----------|-------|-------------|
| V70 | Low | Rotation guard blocks navigator task claims | `check-task-claim.sh` doesn't distinguish "claiming a drive task" from "claiming a nav task." A navigator who just drove can't claim their nav task without a workaround (publish READY, switch to waiting_on_driver). Fix: check whether the claimed task is a nav task (e.g., task description contains "nav" or task ID ends in "-nav") and exempt it from the rotation guard. |
| V71 | Low | Missing task header breaks rotation guard | If a driver skips `session task`, the rotation guard can't see that agent drove. Enforce task header logging via hook (e.g., check LOG.md for `## Task` header before allowing TaskUpdate to in_progress), or have `update-task-state.sh` write a fallback header. |

### Protocol / workflow (new)

| ID | Priority | Title | Proposed fix |
|----|----------|-------|-------------|
| V72 | Low | Advice ID format drift | Navigators use informal IDs (O1, S1) instead of `OBJ-{task}-{seq}` format. Resolution detection in hooks depends on exact ID matching. Add validation to `session advice` that rejects IDs not matching `(OBJ|SML|STR|FYI)-\w+-\d+` pattern, or add a protocol note making the format mandatory. |
| V73 | Low | Advisor idle — use /loop for periodic review | Instead of relying on advisors to self-motivate idle reviews, have the lead set up `/loop 3m` with a prompt that checks `context-store.log` for recent edits and triggers a mini-review. This makes the context-store.log review pattern mechanical rather than behavioral. Add to lead skill's spawn instructions for advisor role. |

### Hook implementation nits

| ID | Priority | Title | Proposed fix |
|----|----------|-------|-------------|
| ~~V69~~ | ~~Low~~ | ~~Multiple stale drivers — only last message retained~~ | ~~Done.~~ Accumulation pattern in `context-store-mark-dirty.sh`. |

---

## Deferred

Items confirmed but not worth the implementation cost. Validated 2026-04-04.

| ID | Title | Priority | Fix type | Notes |
|----|-------|----------|----------|-------|
| V51 | Enforce paired drive+navigate tasks | Medium | Hook | Same blocker as V53: no system-to-session task ID mapping at hook time. Lead skill already enforces pairing structurally (SKILL.md Step 3). Hook can't query other tasks to verify a navigate task exists. |
| V53 | Block self-navigation on same work | Medium | Hook | System-to-session task ID mapping still missing. Can't correlate which drive/navigate tasks belong to the same logical work at hook time. |
| V44 | Consider BLOCKED advice type | Low | Protocol | No evidence of OBJECTION misuse for non-correctness blocks. OBJECTION covers "this is wrong"; forward-progress blocks go via SendMessage to lead. Revisit if misuse pattern emerges. |
| V13 | Context store doesn't surface stale reads at rotation time | Medium | Hook + Protocol | Protocol rule 16 explicitly covers this ("check before editing shared files"). No hookable rotation event exists. |
| AA26 | `lockf` is macOS-only | Low | Hook | Only `context-store-mark-dirty.sh` uses `lockf` now (`context-store-update-read.sh` was deleted). No Linux target documented. |
| AA24 | `color: magenta` invalid + `color` not in frontmatter allowlist | Low | Config | `visual-designer.md` and `code-reviewer.md` both use `color: magenta`. No runtime issues observed. |
| H8 | Shell profile echo breaks JSON | Low | Docs | Platform concern. Official Claude Code docs already cover mitigation. Low value to duplicate. |

---

## Completed

Full details are in git history. Grouped by session for traceability.

| Session | Date | Count | Theme | Key IDs |
|---------|------|-------|-------|---------|
| 1 | 2026-04-02 | 32 | Core hook semantics, protocol scaffolding, shutdown lifecycle | H1–H6, S1–S10, P1–P9, A1–A5, AT1–AT4, N1–N3, R1–R4 |
| 2 | 2026-04-02 | 3 | Retro reliability and notification hooks | R5, R10 (re-opened), R11 |
| 3 | 2026-04-03 | 15 | Shutdown deadlock, context store, task claim enforcement | AA1, V2–V6, V9–V11, P12–P20 |
| 4 | 2026-04-03 | 9 | Agent phase state, READY artifact, write sets, compaction | P10/P11/P17, V8, P18, S3-1–S5-1 |
| 5 | 2026-04-03 | 8 | Paired task model, session script extraction, hook rationalization | Per git (19e2627–0981351) |
| 6 | 2026-04-04 | 7 | CLI task timer tool (demo) | Per task-timer session log |
| 7 | 2026-04-04 | 10 | READY naming, task-correct, bench phase, shutdown terminal state | V32–V40 |
| 8 | 2026-04-04 | 9 | One-driver-at-a-time, rotation enforcement, path normalization | V45, V49–V58. V53 deferred |
| 9 | 2026-04-04 | 9 | Backlog sweep: dedup guards, write-set, TTL, status cmd, docs | V42, V59, V61, V62, V64, V65, V67, AA27 |
| 10 | 2026-04-04 | 3 | Code-review fixes: dedup anchoring, V61 conservative fallback, TTL tests | F1 (V61 malformed-date hard block), F2 (V64 anchor), F3 (V65 anchor) |
| 11 | 2026-04-04 | 7 | Backlog sweep: all open items cleared (hooks, protocol, docs) | V43, V46, V47, V68, V69, AA23, AA28 |
| — | 2026-04-03 | 17 | Closed — invalid, already fixed, or superseded | AA2, AA3, AA5, AA11, AA29, P20, R6, R7–R9, V12, V31, V41, V48, V63, V66 |

120 items completed across 11 sessions. 231 tests at last count.
