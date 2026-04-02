# Popcorn XP Backlog

Living backlog for popcorn-xp improvements. Items are added from session retros and periodic audits.

## Status Key

| Status | Meaning |
|--------|---------|
| Done | Applied and verified |
| Deferred | Acknowledged, not yet prioritized |
| Open | Needs work |

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

---

## Deferred

| ID | Title | Priority | Source | Notes |
|----|-------|----------|--------|-------|
| H8 | Shell profile echo breaks JSON | Low | Session 1 | Docs-only item, no code change needed |

---

## Open (from Session 2 retro — 2026-04-02 layout workspace)

| ID | Title | Priority | Source | Notes |
|----|-------|----------|--------|-------|
| R5 | Agents SendMessage lead after writing retro | Medium | Session 2 retro | PostToolUse on Write + FileChanged on lead. Prerequisite: R11. [details](#r5--agents-sendmessage-lead-after-writing-retro) |
| R6 | Require explicit OBJECTION confirmation in task completion | Medium | Session 2 retro | Protocol change + optional TaskCompleted hook. Related: H3. [details](#r6--require-explicit-objection-confirmation-in-task-completion) |
| R7 | Suppress or annotate duplicate message echo | Medium | Session 2 retro | Protocol-only (no platform mechanism). **Follow-up to P5.** [details](#r7--suppress-or-annotate-duplicate-message-echo) |
| R8 | Tighten retro prompt: process only | Low | Session 2 retro | Prompt-only. **Follow-up to R2.** [details](#r8--tighten-retro-prompt-process-only) |
| R9 | Schema validation as test pattern | Low | Session 2 retro | Downstream guidance, not a plugin change. [details](#r9--schema-validation-as-test-pattern) |
| R10 | Lead retro-file awareness via FileChanged hook | Medium | Session 2 retro | FileChanged hook on `\.retro-.*\.md` + SKILL.md Step 6. Prerequisite: R11. [details](#r10--lead-retro-file-awareness-via-filechanged-hook) |
| R11 | Retro file reliability on shutdown | Medium | Session 2 retro | Reorder enforce-no-idle phases. Prerequisite for R5, R10. [details](#r11--retro-file-reliability-on-shutdown) |

### Solution Notes

#### R5 — Agents SendMessage lead after writing retro

Closes visibility gap — lead doesn't know retro file landed without checking filesystem.

**Platform:** `PostToolUse` hook on `Write` can be added to agent frontmatter (hooks-ref: hooks in skills and agents are scoped to the component's lifecycle). Detects `.retro-*.md` writes and injects `additionalContext` nudging the agent to SendMessage the lead. On the lead side, a `FileChanged` hook (hooks-ref: matcher is regex on basename) watching `\.retro-.*\.md` injects context when retro files appear.

**Fix:** Two changes: (1) Add PostToolUse Write hook to agent definitions that detects retro file writes and injects "You just wrote your retro file. SendMessage the lead to confirm." (2) Add FileChanged hook to lead skill or hooks.json watching for retro file arrivals. Prerequisite: R11 must be fixed first — if the retro file never gets written due to the race condition, these hooks have nothing to trigger on.

#### R6 — Require explicit OBJECTION confirmation in task completion

"OBJ-11-01: fixed (Panel gets flex-column)" rather than silent resolution.

**Platform:** `TaskCompleted` hooks fire on every occurrence with no matcher support (hooks-ref). A hook script could scan ADVICE.md for OBJECTIONs assigned to the completing agent and block (exit 2) if any lack explicit confirmation in the completion message. Related: H3 (Session 1) fixed the ID pattern in `check-advice-on-complete.sh`, which already scans for unresolved OBJECTIONs — R6 extends that pattern from "are they resolved?" to "are they explicitly confirmed in the completion message?"

**Fix:** Two changes: (1) Update the protocol's task completion format to require "OBJ-{id}: {outcome} ({summary})" lines. (2) Optionally extend check-advice-on-complete.sh to verify OBJECTIONs appear in the TaskCompleted input's description.

#### R7 — Suppress or annotate duplicate message echo

3/4 agents flagged echoed task assignments as confusing. **Follow-up to P5** which only addressed the receiver side.

**Platform:** No hook event fires on incoming message receipt — hooks only cover tool use, idle, stop, and session events. The agent-teams docs acknowledge "Task status can lag" as a known limitation. No hook-based suppression is possible with the current platform.

**Fix:** Add to protocol skill's Core Rules section: "After completing a task, you may receive echoed copies of your original task assignment message. These are platform delivery artifacts, not re-assignments. Ignore them and continue with your next task." Also add to `references/protocol.md` driver and navigator prompts in the Important section.

#### R8 — Tighten retro prompt: process only

**Follow-up to R2** which added retro instructions but wasn't specific enough. Agents still mixed in implementation details.

**Platform:** Prompt-only change. No hooks needed.

**Fix:** Update protocol skill's Retro section and references/protocol.md to add: "Do NOT describe what you built or what bugs you found — that's in LOG.md. Focus on the collaboration process: pairing dynamic, advice quality, checkpoint frequency, rotation, communication friction."

#### R9 — Schema validation as test pattern

OBJ-9-01/02/03 were schema violations only caught by code review.

**Platform:** Not a popcorn-xp plugin change — this is guidance for downstream projects using popcorn-xp.

**Fix:** Add a recommendation to the lead skill's code review task template: "If the project defines schemas (JSON Schema, TypeScript types, Zod, etc.), recommend the team add programmatic validation tests rather than relying on code reviewers to catch structural violations."

#### R10 — Lead retro-file awareness via FileChanged hook

Merges two symptoms of the same root cause: (1) lead wrote RETRO.md before QA's `.retro-qa.md` landed (premature close-out), (2) lead incorrectly told the user that agents don't auto-write retro files (they do, via enforce-no-idle's retro-pending phase). Both stem from the lead lacking visibility into `.retro-*.md` arrivals.

**Platform:** `FileChanged` hook (hooks-ref: matcher is regex on basename) can watch `\.retro-.*\.md` on the lead's session. When a retro file lands, inject `additionalContext` like "Retro file received: .retro-{name}.md. {N} of {M} expected retros collected." Agent-teams docs confirm "idle notifications: when a teammate finishes and stops, they automatically notify the lead" — the lead already gets stop notifications, but doesn't check for retro files at that point.

**Fix:** Two changes: (1) Add FileChanged hook to hooks.json or lead skill watching `\.retro-.*\.md`, injecting retro arrival context. (2) Update SKILL.md Step 6 to make the wait explicit: "After retro-request, wait for all `.retro-*.md` files before writing RETRO.md. The FileChanged hook will notify you as each one arrives." Prerequisite: R11 must be fixed first — if retro files aren't reliably written, FileChanged has nothing to trigger on.

#### R11 — Retro file reliability on shutdown

Tester shut down without `.retro-tester.md` — 1 of 3 missing retro files. Scout and visual-designer were advisory single-task agents that shut down before retro-request (expected). But tester was a multi-task driver who should have received the retro-request. Prerequisite for R5 and R10: the FileChanged hooks are useless if the retro file doesn't get written.

**Platform:** TeammateIdle is the only enforcement point for teammates (SubagentStop only fires for subagents, not teammates — hooks-ref confirms different events). The race condition: if `.shutdown` is set before `.retro-requested`, enforce-no-idle's phase 1 (shutdown → force-stop via `{"continue": false}`) fires before phase 2 (retro-pending → nudge retro). Agent-teams docs note "Shutdown can be slow: teammates finish their current request or tool call before shutting down."

**Fix:** Two changes: (1) Reorder enforce-no-idle phases — check retro-pending BEFORE shutdown. If both `.retro-requested` and `.shutdown` exist but `.retro-{agent}.md` doesn't, nudge retro instead of force-stopping. Only force-stop after retro is written (or after a timeout cycle). (2) Lead should SendMessage a retro request to each agent BEFORE issuing the stop, giving the agent a turn to write it while still active.
