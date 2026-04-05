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
| ~~V70~~ | ~~Low~~ | ~~Rotation guard blocks navigator task claims~~ | ~~Done.~~ `check-task-claim.sh` now exempts nav tasks from the back-to-back rotation guard when the claim ID or description identifies navigation work. |
| ~~V71~~ | ~~Low~~ | ~~Missing task header breaks rotation guard~~ | ~~Done.~~ `update-task-state.sh` now seeds a fallback `## Task ... (auto)` header when the current task has no header yet, so `check-task-claim.sh` still has a stable rotation anchor without blocking the claim. |

### Protocol / workflow (new)

| ID | Priority | Title | Proposed fix |
|----|----------|-------|-------------|
| ~~V72~~ | ~~Low~~ | ~~Advice ID format drift~~ | ~~Done.~~ `session advice` now rejects informal IDs before appending to `ADVICE.md`, and the protocol docs call out the canonical `OBJ/SML/STR/FYI-{task}-{seq}` format. |
| ~~V73~~ | ~~Low~~ | ~~Advisor idle — use /loop for periodic review~~ | ~~Done.~~ `skills/popcorn-xp/SKILL.md` now tells the lead to put long-lived advisors on a `/loop 3m` review cadence that rereads `context-store.log` and recent touched files. |
| ~~V80~~ | ~~Medium~~ | ~~Block navigator/advisor edits via hook~~ | ~~Done (session 13).~~ Role guard added to `context-store-mark-dirty.sh` — navigator/advisor edits blocked, .popcorn-xp/* paths exempt, fail-open for lead/unknown/no-state. 6 tests added. |
| ~~V79~~ | ~~High~~ | ~~Canonicalize 3-member team + lead lens~~ | ~~Done (session 13).~~ Lead lens added to SKILL.md. Role Roster updated to 3-core default with navigator=read-ahead / advisor=log-watcher split. Supplemental roles section added. protocol.md "Suggested First Task Assignment" updated to 3, Supplemental Agents section added, advisor prompt rewritten with log-watch as primary standing work. |
| ~~V81~~ | ~~Medium~~ | ~~Advisor review cursor — idle hook enforces log review~~ | ~~Done (session 13).~~ `cs_review_cursor_file()` and `cs_edit_count_since_review_cursor()` added to context-store-log.sh. Phase 5e-adv added to enforce-no-idle.sh. `session review {agent}` subcommand added to bin/session. 3 tests added. |
| ~~V82~~ | ~~Medium~~ | ~~Task acceptance criteria ("Done when:")~~ | ~~Done (session 13).~~ "Done when:" added to drive task template and T1/T2/T3 examples in SKILL.md. Checklist item 6 "The done test" added to decomposition checklist. |
| ~~V83~~ | ~~Medium~~ | ~~Session goal — one sentence stated in Step 1~~ | ~~Done (session 13).~~ Session goal instruction added to Step 1 (before decomposition). Monitor bullet references session goal for scope decisions. Retro template updated with "Session goal: {goal}. Met: yes/no." |
| ~~V84~~ | ~~Low~~ | ~~Lead as unblocker, not observer~~ | ~~Done (session 13).~~ "Unblock, don't observe" bullet added to Monitor section, combined with V83 session goal anchor. |

### Simplification

| ID | Priority | Title | Proposed fix |
|----|----------|-------|-------------|
| ~~V74~~ | ~~Medium~~ | ~~Kill context-store.json — derive state from log~~ | ~~Done (session 13).~~ `cs_file_state()` added to context-store-log.sh. context-store-check.sh, context-store-mark-dirty.sh, cleanup-context-store.sh all updated. context-store.json eliminated. 246 tests passing after update. |
| ~~V75~~ | ~~Medium~~ | ~~Extract shared advice-counting function~~ | ~~Done (session 13).~~ `px_unresolved_advice()` added to session-common.sh. check-advice-on-complete.sh and enforce-no-idle.sh refactored to use it. |
| ~~V76~~ | ~~Low~~ | ~~Collapse enforce-no-idle Phase 5e branching~~ | ~~Done (session 13).~~ ~20 lines of duplicated branching removed. Single advice block with waiting_on_driver OBJ-only fast path. |
| ~~V77~~ | ~~Low~~ | ~~Deduplicate `px_normalize_agent` branches~~ | ~~Done (session 13).~~ Empty/null/unknown merged into single condition. |
| ~~V78~~ | ~~Low~~ | ~~Bake `updated_at` into `px_update_state`~~ | ~~Done (session 13).~~ Timestamp auto-injected in px_update_state. All 4 call sites updated. |

### Shutdown lifecycle

| ID | Priority | Title | Proposed fix |
|----|----------|-------|-------------|
| V85 | High | `{"continue": false}` from TeammateIdle hook does not stop agents | Session 13 proved this empirically: craftsman's state was updated to `phase=shutdown` by Phase 2 in `enforce-no-idle.sh`, confirming the hook ran and output `{"continue": false, "stopReason": "..."}` with exit 0. But the agent did not terminate — it continued idling. Exit 0 from a TeammateIdle hook means "allow idle"; the system treats stdout as `additionalContext` JSON, not as a control signal. The only mechanism that actually terminates agents is `shutdown_request` via SendMessage. **Evidence:** craftsman.json shows `phase=shutdown` but agent was still alive; expert.json shows `phase=completed` (Phase 2 ran for craftsman, not expert, because craftsman hit the hook first after `.shutdown` was created); tester.json shows `phase=waiting_on_driver` (hook never reached Phase 2 — Phase 5a allowed idle first, or Phase 2 ran but `{"continue": false}` was ignored). All 3 agents only stopped after explicit `shutdown_request` messages. **Fix:** (1) Change `enforce-no-idle.sh` Phase 2 to output the stop signal via stderr + exit 2 instead: `echo "Session complete — shutting down." >&2; exit 2` — this blocks the agent and gives it the shutdown message as feedback. Or (2) Accept that hook-based shutdown doesn't work and change the protocol to always send `shutdown_request` messages. Option 2 is simpler and proven. Update SKILL.md Step 6 to remove "You do not need to send shutdown_request messages" and make `shutdown_request` the canonical shutdown mechanism. Phase 2 in enforce-no-idle becomes a reminder ("shutdown in progress, approve the shutdown_request") rather than the stop mechanism itself. |
| V86 | Medium | Rotation hook blocks nav task claims despite V70 fix | Session 13: `check-task-claim.sh` blocked craftsman from claiming nav tasks after driving, requiring lead to pre-assign every pair transition. V70 added `px_is_nav_task` exemption but it's not matching. **Investigate:** The hook receives the system task ID and description, not the session task ID. `px_is_nav_task` checks for "nav/navigate/navigator" in the task ID or description — but post-compaction, the task metadata may not contain those keywords (the system task subject is what TaskCreate provided). Check whether the task subjects from this session actually contain "nav" — they do ("T1 nav:", "T2 nav:", etc.), so the hook should have matched. Possible cause: the hook is checking `$TASK_ID` from agent-state (the session task ID, e.g., "12") rather than the system task description. The session task ID "12" doesn't contain "nav". **Fix:** Pass the system task description (from the hook input JSON) to `px_is_nav_task` in addition to the agent-state task ID. |
| V87 | Low | Compaction recovery protocol | Session 13: both expert and craftsman received echoed assignments for completed tasks after context compaction, causing confusion and wasted cycles. **Fix:** Add a "Compaction Recovery" section to `skills/popcorn-xp-protocol/SKILL.md` teammate protocol: "After context compaction, before resuming work: (1) Check TaskList for current task status, (2) Read LOG.md for latest checkpoints, (3) Read ADVICE.md for any open items, (4) Check git log for recent commits. Do not re-do work that's already complete. Ignore assignment messages that reference already-completed tasks." This text already exists in the driver/navigator prompt templates in protocol.md — promote it to the auto-loaded protocol skill so all agents get it. |
| V88 | Low | AA26 lockf removed — close deferred item | V74 (session 13) removed the `lockf` call from `context-store-mark-dirty.sh`. AA26 ("lockf is macOS-only") is no longer relevant. Move from Deferred to Completed. |
| V89 | Medium | `session ready` hardcodes role=navigator, breaking advisor state | `bin/session` line 118: the `ready` subcommand sets `.role = "navigator"` unconditionally. When an advisor runs `session ready` to publish a READY artifact, their role is silently overwritten from `advisor` to `navigator`. **Session 13 evidence:** Tester was spawned as advisor (`session state tester advisor monitoring`) but ended the session with `role=navigator, phase=waiting_on_driver` — because tester ran `session ready` to publish a correctness_review artifact. This broke V81: the advisor review cursor check (`role=advisor`) never fired because tester's role was no longer `advisor`. **Fix:** `session ready` should preserve the existing role instead of hardcoding navigator. Change line 118 to read the current role first: `current_role=$(jq -r '.role // "navigator"' "$file")` then use `$current_role` in the merge. Only default to "navigator" if no role is set. |
| V90 | Low | ADVICE.md doesn't record advice author | The `session advice` command appends `### TYPE ID — open` with no attribution. During session 13 retro, OBJ-T1-01 and OBJ-1-01 couldn't be reliably attributed to expert vs tester from session files alone — the retro had to guess based on role timing. **Fix:** Add an optional author field: `session advice TYPE ID AUTHOR "description"`. Format: `### TYPE ID — open (by {author})`. Backward-compatible: if AUTHOR is omitted, no attribution. Resolution matching is unaffected (it only checks ID). |

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
| 12 | 2026-04-04 | 4 | Navigator claims, fallback task anchors, advice ID validation, advisor loop | V70–V73 |
| 13 | 2026-04-04 | 11 | Backlog sweep: context-store.json elimination, advice extraction, simplification trio, role guard, advisor cursor, protocol canonicalization | V74–V84 |
| — | 2026-04-03 | 17 | Closed — invalid, already fixed, or superseded | AA2, AA3, AA5, AA11, AA29, P20, R6, R7–R9, V12, V31, V41, V48, V63, V66 |

135 items completed across 13 sessions. 259 tests at last count.
