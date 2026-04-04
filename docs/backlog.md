# Popcorn XP Backlog

Living backlog for popcorn-xp improvements. Items are added from session retros and periodic audits.

## Legend

| Column | Values |
|--------|--------|
| Priority | Critical, High, Medium, Low |
| Fix type | Hook = shell script change, Protocol = SKILL.md / protocol text, Docs = architecture / CLAUDE.md, Config = agent frontmatter |
| Status | Open, Deferred, Done |

---

## Open — Critical & High

These block correct shutdown, cause double work, or represent dead hooks.

| # | ID(s) | Title | Fix type | Batch | Notes |
|---|-------|-------|----------|-------|-------|
| 1 | AA1 | Shutdown deadlock: parallel TeammateIdle hooks override force-stop | Hook | 1 | **Done (Session 3).** Added `.shutdown` early-exit to `remind-unread-advice.sh` and `remind-checkpoint.sh`. |
| 2 | V6, P12, P20 | Agent self-assignment / shutdown race / lifespan enforcement | Hook + Protocol | 4 | **Done (Session 3).** `check-task-claim.sh` (PreToolUse:TaskUpdate) + `update-task-registry.sh` (PostToolUse:TaskUpdate) + `.task-registry` file. Blocks post-shutdown claims and concurrent claims. |
| 3 | V9, V10 | Retro notification chain is dead (both hooks never fire) | Protocol | 1 | **Done (Session 3).** Removed dead `notify-retro-written.sh` and `notify-retro-received.sh` hooks from `hooks.json`. Added SendMessage-based retro notification guidance to protocol. |
| 4 | P10, P11, P17 | Navigator role ineffective — all navigators go idle after 1-2 messages | Protocol | 5 | **Done (Session 4).** Added explicit agent phase state, mandatory navigator READY artifacts, and waiting-state-aware idle enforcement. |
| 5 | P13 | Session script breaks on CWD change | Hook | 2 | **Done (Session 3).** SKILL.md session template heredoc changed from `<< 'SCRIPT'` to `<< SCRIPT`; DIR bakes in team name at write time. |
| 6 | V5 | Agents don't reliably act on TeammateIdle hook stderr | Protocol | 3 | **Done (Session 3).** Lead monitoring guidance strengthened to require direct SendMessage for critical actions. |

## Open — Medium

Functional gaps, accuracy issues, and protocol holes.

| # | ID(s) | Title | Fix type | Batch | Notes |
|---|-------|-------|----------|-------|-------|
| 7 | V2 | Context store preview field causes token bloat (17K+ for 11 files) | Hook | 2 | **Done (Session 3).** `context-store-update-read.sh` now truncates preview to first 10 lines via `head -10`. |
| 9 | V8 | `enforce-no-idle` can't distinguish waiting-for-partner from truly idle | Hook + Protocol | 5 | **Done (Session 4).** Added explicit `waiting_on_driver` / `waiting_on_verification` phases plus READY artifact gating. |
| 10 | V11 | `check-objections.sh` (SubagentStop) never fires for team members | Hook | 1 | **Done (Session 3).** Added OBJECTION check to `enforce-no-idle.sh` shutdown phase — blocks with exit 2 and resolve instructions when unresolved OBJECTIONs exist at shutdown. |
| 11 | V13 | Context store doesn't surface stale reads at rotation time | Hook + Protocol | — | **Confirmed.** No rotation-triggered summary exists. **Deferred** — protocol already says "re-read files before driving"; mechanical hook adds complexity for marginal value. |
| 12 | V1 | Context store `read_by` only tracks last reader | Hook | — | **Confirmed.** `context-store-update-read.sh` overwrites on each read. The log file has full history. Fix if convenient or accept limitation. |
| 14 | AA4 | Lead session reads attributed to "unknown" in context store | Hook | 2 | **Done (Session 3).** All three context store hooks now fall back to `"lead"` when `CLAUDE_CODE_COORDINATOR_MODE` is set and `agent_type` is unknown. |
| 15 | R6 | Require explicit OBJECTION confirmation in task completion message | Hook + Protocol | — | **Protocol addressed, not mechanically enforced.** `check-advice-on-complete.sh` checks resolutions exist in ADVICE.md but does not grep completion message. **Deferred** — current check catches the real problem; requiring text in messages is fragile. |
| 17 | P14 | Agents don't declare intent before going idle | Protocol | 3 | **Done (Session 3).** Intent declaration added to protocol core rules. |
| 18 | P15 | Context compaction risks re-driving completed work | Protocol | 3 | **Done (Session 3).** Post-compaction checklist added to protocol (check git log, TaskList, ADVICE.md before driving). |
| 19 | P16 | ADVICE.md resolutions need file:line citations | Protocol | 3 | **Done (Session 3).** Protocol wording updated to require file:line format in resolution details. |
| 20 | P18 | Mocked hooks gave false confidence — need integration test guidance | Docs | 5 | **Done (Session 4).** Added replay-fixture coverage in `test-hooks.sh` and documented the live-session gap explicitly. |
| 34 | S3-1 | Parallel agents need file ownership convention | Protocol | 5 | **Done (Session 4).** Task creation now requires declared write sets for parallel work; context-store hook blocks edits outside the write set. |
| 35 | S3-2 | Navigator "ready for implementation" signal | Protocol | 5 | **Done (Session 4).** Added `session ready` artifact plus hook enforcement before waiting is allowed. |
| 36 | S3-3 | Design alignment step before complex implementation tasks | Protocol | 5 | **Done (Session 4).** Added `ambiguity: ambiguous` handshake requirement before first edit. |

## Open — Low

Docs cleanup, cosmetic issues, and edge cases.

| # | ID(s) | Title | Fix type | Batch | Notes |
|---|-------|-------|----------|-------|-------|
| 23 | AA6 | Lens text drift across source files | Docs | — | **Confirmed, minor.** Truncations between `agents/*.md` (canonical) and SKILL.md/architecture doc. Fix incidentally when touching those files. |
| 24 | AA7, AA8 | `color: magenta` invalid + `color` not in frontmatter allowlist | Config | — | **Confirmed.** `visual-designer.md` and `code-reviewer.md` both use `color: magenta`. Cosmetic — **deferred** unless it causes runtime issues. |
| 25 | AA9 | Redundant `references/protocol.md` body reference in 8 agents | Config | 3 | **Done (Session 3).** All 8 agents updated — body now says "protocol auto-loaded via the `popcorn-xp-protocol` skill." |
| 26 | AA10 | `lockf` is macOS-only | Hook | — | **Confirmed.** `context-store-update-read.sh` and `context-store-mark-dirty.sh` use `lockf`. **Deferred** — no Linux target documented. |
| 27 | AA12 | Context store JSON example misleading in architecture doc | Docs | — | **Confirmed.** Example shows `edited_by`/`edited_at` as always-present; only appear after edit. Fix incidentally when touching docs. |
| 28 | AA13 | `check-rotation.sh` missing `.active-team` guard | Hook | 2 | **Done (Session 3).** Guard added — exits 0 when no `.active-team` file present. |
| 29 | AA14 | `CLAUDE_CODE_COORDINATOR_MODE` undocumented | Docs | — | **Confirmed.** Referenced in 7+ files, 0 in official Claude Code docs. Fix: document as experimental in README/CLAUDE.md. |
| 30 | V3 | Context store tracks files outside project directory | Hook | 2 | **Done (Session 3).** All three context store hooks skip files where path doesn't start with `$CLAUDE_PROJECT_DIR`. |
| 31 | V7 | Session script bootstrapping gap | Docs | — | **Confirmed as inherent design limitation.** Template changes don't propagate to running sessions. Fix: document the limitation. Upgrade subcommand adds complexity for a rare edge case. |
| 33 | P19 | Linter hooks reverting writes causes agent confusion | Protocol | 3 | **Done (Session 3).** Protocol guidance note added about linter hooks and post-write content mismatches. |

## Implementation Batches

Recommended order based on code-scout investigation (2026-04-03). **All batches completed in Session 3 (2026-04-03).**

| Batch | Theme | Tickets | Status |
|-------|-------|---------|--------|
| 1 | Shutdown reliability | #1 (AA1), #3 (V9/V10), #10 (V11) | **Done** |
| 2 | Quick hook fixes | #5 (P13), #7 (V2), #14 (AA4), #28 (AA13), #30 (V3) | **Done** |
| 3 | Protocol text updates | #6 (V5), #17 (P14), #18 (P15), #19 (P16), #25 (AA9), #33 (P19) | **Done** |
| 4 | Task claim enforcement | #2 (V6/P12/P20) — new PreToolUse:TaskUpdate hook | **Done** |

**Deferred pending discussion:** #11 (stale read surfacing), #15 (OBJECTION in completion msg)

**New from Session 3 retro:** #34 (file ownership convention), #35 (navigator ready signal — relates to #4), #36 (design alignment step)

**Fix incidentally:** #23 (lens drift), #27 (JSON example)

---

## Deferred

| ID | Title | Priority | Source | Notes |
|----|-------|----------|--------|-------|
| H8 | Shell profile echo breaks JSON | Low | Session 1 | Docs-only item, no code change needed |

---

## Completed (Session 1 — 2026-04-02)

| ID | Title | Source | Notes |
|----|-------|--------|-------|
| H6 | `systemMessage` -> `additionalContext` | Session 1 | All 4 scripts updated |
| H1 | TeammateIdle must exit 2 | Session 1 | remind-unread-advice.sh, remind-checkpoint.sh |
| H2 | Unconditional no-idle hook | Session 1 | enforce-no-idle.sh created |
| H3 | Fix ID pattern in enforcement | Session 1 | check-advice-on-complete.sh, remind-unread-advice.sh, check-objections.sh |
| H4 | Case-insensitive resolution matching | Session 1 | `-i` flag on all resolution greps |
| H5 | Fix block output channel | Session 1 | All exit-2 paths use plain text stderr |
| S8 | `disable-model-invocation: true` | Session 1 | Frontmatter enforcement |
| P1 | Context limit + handoff | Session 1 | Driver and navigator prompts |
| P2 | Handoff format definition | Session 1 | Session Files section |
| P3 | `session handoff` command | Session 1 | Session script template |
| P4 | Verification before complete | Session 1 | Driver step 7a, SKILL.md Step 2, Quality Bar |
| P5 | Check messages before claiming | Session 1 | Driver step 1 |
| P6 | Advice dual-write mandatory | Session 1 | Navigator step 1c |
| P7 | Per-edit logging as numbered step | Session 1 | Step 5 split into 5a/5b |
| P8 | Task headers mandatory | Session 1 | `task` subcommand added |
| P9 | Log advice in LOG.md | Session 1 | Driver step 6 |
| S1 | Lead handles handoff requests | Session 1 | Monitor section |
| S2 | Fresh agent for QA | Session 1 | Step 3 task breakdown |
| S3 | ID convention for reviewer relays | Session 1 | Monitor section |
| S4 | Open SMELL audit at close | Session 1 | Step 6 item 3 |
| S5 | Parallel scout as default | Session 1 | Step 3 |
| S6 | Two-phase review as task | Session 1 | Step 3 |
| S7 | Task sizing for rotation | Session 1 | Replaced "don't create thin tasks" with user-value test |
| S9 | Dynamic context injection | Session 1 | Backtick syntax in SKILL.md preamble |
| S10 | Protocol via `skills` field | Session 1 | All 9 agent definitions |
| A1 | `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=70` | Session 1 | Step 2 setup |
| A2 | `maxTurns` as context budget | Session 1 | Step 4, 80-120 turns |
| A3 | SendMessage resume | Session 1 | Monitor section |
| A4 | `memory: project` on expert | Session 1 | Already existed |
| A5 | Navigator no-edit: prompt-only | Session 1 | Kept as-is |
| AT1 | Task status lag check | Session 1 | Monitor section |
| AT2 | Plan approval mode | Session 1 | Step 4 optional pattern |
| AT3 | Session resumption note | Session 1 | Session Files section |
| AT4 | Throughput vs rotation tension | Session 1 | Folded into S7 |
| N1 | Permission pre-approval | Session 1 | Step 2 setup |
| N2 | Team cleanup sequencing | Session 1 | Step 6 reordered |
| N3 | Orchestrator trap guard | Session 1 | Monitor section |
| R1 | Batch checkpoint allowance | Session 1 | protocol.md, protocol skill |
| R2 | Retro instructions in protocol | Session 1 | protocol skill, driver/navigator prompts |
| R3 | Soft checkpoint frequency enforcement | Session 1 | mark-dirty.sh, remind-checkpoint.sh |
| R4 | Mechanical shutdown lifecycle enforcement | Session 1 | enforce-no-idle.sh, session script, SKILL.md, protocol |

## Completed (Session 2 — 2026-04-02)

| ID | Title | Source | Notes |
|----|-------|--------|-------|
| R5 | Agents SendMessage lead after writing retro | Session 2 retro | `notify-retro-written.sh` (PostToolUse Write). **Re-opened as V9**: agents use Bash, not Write tool |
| R10 | Lead retro-file awareness via FileChanged hook | Session 2 retro | `notify-retro-received.sh` (FileChanged). **Re-opened as V10**: FileChanged never fires for subdirectory retro files |
| R11 | Retro file reliability on shutdown | Session 2 retro | `enforce-no-idle.sh` phase reorder. Verified working in hook-validation session |

## Completed (Session 3 — 2026-04-03)

| ID | Title | Source | Notes |
|----|-------|--------|-------|
| AA1 | Shutdown deadlock: parallel TeammateIdle hooks override force-stop | Batch 1 | Added `.shutdown` early-exit guards to `remind-unread-advice.sh` and `remind-checkpoint.sh` |
| V9, V10 | Retro notification chain is dead (both hooks never fire) | Batch 1 | Removed unreachable `notify-retro-written.sh` and `notify-retro-received.sh` from `hooks.json`; added SendMessage guidance to protocol |
| V11 | `check-objections.sh` (SubagentStop) never fires for team members | Batch 1 | Added OBJECTION check to `enforce-no-idle.sh` shutdown phase — blocks (exit 2) with resolve instructions when unresolved OBJECTIONs exist |
| P13 | Session script breaks on CWD change | Batch 2 | SKILL.md session template: unquoted heredoc + escaped variables + hardcoded team name in DIR |
| V2 | Context store preview field causes token bloat (17K+ for 11 files) | Batch 2 | `context-store-update-read.sh`: limited preview to first 10 lines via `head -10` |
| AA4 | Lead session reads attributed to "unknown" in context store | Batch 2 | All three context store hooks: added fallback to `"lead"` when `CLAUDE_CODE_COORDINATOR_MODE` is set |
| AA13 | `check-rotation.sh` missing `.active-team` guard | Batch 2 | Added early exit when no `.active-team` file present |
| V3 | Context store tracks files outside project directory | Batch 2 | All three context store hooks: added PROJECT_DIR boundary check (skip external files) |
| V5 | Agents don't reliably act on TeammateIdle hook stderr | Batch 3 | Lead monitoring guidance: require direct SendMessage for critical actions instead of relying on stderr parsing |
| P14 | Agents don't declare intent before going idle | Batch 3 | Added Rule 10 to protocol core rules: "Declare intent. Before going idle or switching focus, state what you plan to do next via SendMessage." |
| P15 | Context compaction risks re-driving completed work | Batch 3 | Added post-compaction recovery checklist to protocol context limit section (4 steps) |
| P16 | ADVICE.md resolutions need file:line citations | Batch 3 | Protocol guidance updated to require `file:line` format in resolution details |
| P19 | Linter hooks reverting writes causes agent confusion | Batch 3 | Added Important Notes section to protocol with guidance on linter hook behavior |
| AA9 | Redundant `references/protocol.md` body reference in 8 agents | Batch 3 | Updated all 8 agent files: body now says "protocol auto-loaded via the `popcorn-xp-protocol` skill" |
| V6, P12, P20 | Agent self-assignment / shutdown race / lifespan enforcement | Batch 4 | New `check-task-claim.sh` (PreToolUse:TaskUpdate) blocks post-shutdown claims and concurrent claims. New `update-task-registry.sh` (PostToolUse:TaskUpdate) maintains `.task-registry` TSV. P20 lifespan limits deferred — no protocol-defined numeric limit |

## Completed (Session 4 — 2026-04-03)

| ID | Title | Source | Notes |
|----|-------|--------|-------|
| P10, P11, P17 | Navigator role ineffective — all navigators go idle after 1-2 messages | Refactor pass | Added explicit `agent-state/*.json`, mandatory READY artifacts, and waiting-state-aware idle enforcement |
| V8 | `enforce-no-idle` can't distinguish waiting-for-partner from truly idle | Refactor pass | Added explicit waiting phases plus READY gating in `enforce-no-idle.sh` |
| P18 | Mocked hooks gave false confidence — need integration test guidance | Refactor pass | Added replay-fixture tests in `tests/test-hooks.sh` and documented replay/live-test split |
| S3-1 | Parallel agents need file ownership convention | Session 3 retro | Lead skill now requires declared write sets; `context-store-mark-dirty.sh` blocks out-of-scope edits |
| S3-2 | Navigator "ready for implementation" signal | Session 3 retro | Added `session ready` command, READY markdown artifact, and hook checks |
| S3-3 | Design alignment step before complex implementation tasks | Session 3 retro | Added `ambiguity: ambiguous` handshake requirement in lead skill and protocol |

## Closed (Validation — 2026-04-03)

| ID | Title | Verdict | Evidence |
|----|-------|---------|----------|
| AA3 | `TeamDelete` PreToolUse matcher unverified | **INVALID** | Hook fired and blocked correctly in live session |
| AA11 | Exit code semantics incomplete in architecture doc | **INVALID** | Table is correct and complete |
| R8 | Tighten retro prompt: process only | **ALREADY FIXED** | Protocol already says "process only" with exclusions |
| R9 | Schema validation as test pattern | **ALREADY FIXED** | Already in code review guidance |

## Closed (Investigation — 2026-04-03)

| ID | Title | Verdict | Evidence |
|----|-------|---------|----------|
| V4, AA15 | Advice bypasses ADVICE.md (DMs only) | **ALREADY FIXED** | Protocol explicitly instructs dual-write; `session advice` commands in spawn prompts validated working |
| AA2 | Agent name double-prefixing risk | **ACCEPTABLE RISK** | All 3 context store hooks already guard with `if ! [[ "$AGENT" =~ ^popcorn-xp: ]]` before prefixing |
| R7 | Duplicate message echo confuses agents | **ALREADY FIXED** | Protocol rule 10 explicitly says "echoed task assignments after completion are platform artifacts — ignore them" |
| AA5 | FileChanged watcher subdirectory scope unclear | **SUBSUMED** | Same root cause as V9/V10 (#3); will be documented when #3 is fixed |
| P20 | Expert exceeded task lifespan limit | **DUPLICATE** | Explicitly covered by V6/P12/P20 cluster (#2) |
| V12 | PostToolUse hooks not logged in debug output | **NOT A BUG** | Platform debug gap, not a popcorn-xp issue; hooks run correctly |
