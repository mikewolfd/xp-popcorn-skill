# Popcorn XP Improvement Backlog

Derived from the `layout-complete` session retro (2026-04-02), ADVICE.md analysis, LOG.md analysis, and review of the canonical hooks and agent-teams documentation. Updated with findings from audit against canonical Anthropic documentation for hooks, agents, agent-teams, and skills (2026-04-02).

---

## Status

| Status | Meaning |
|--------|---------|
| ✅ Done | Applied this session |
| 🔴 Critical | Broken or silently failing right now |
| 🟠 High | Significant quality or correctness gap |
| 🟡 Medium | Process improvement with meaningful impact |
| 🟢 Low | Polish / nice to have |

---

## ✅ Done

### No Idle Hands

**Context:** The `layout-complete` retro noted agents becoming unresponsive in late-session tasks. Separately, the advisor and navigator prompts had explicit "go idle" language when no task was available. An idle agent contributes nothing and wastes a context window.

**Change applied:**
- Added Core Rule 9 to `protocol.md`: "No idle hands. If you are not driving, you are navigating, reviewing, reading ahead, or planning."
- Replaced "go idle — the lead will assign" in driver prompt step 7e with a list of productive activities (review own changes, read ahead, check tests)
- Replaced "go idle" language in navigator prompt with gap-filling directives
- Expanded advisor "How You Work" from passive monitoring to active participation
- Added "No idle agents" bullet to SKILL.md Monitor section with specific lead interventions
- Added "No idle agents" to SKILL.md Quality Bar
- Updated README pairing model section and TeammateIdle hook description

---

## Hooks

### H1 — TeammateIdle must exit 2, not 0
**Priority:** 🔴 Critical

**Context:** The `TeammateIdle` hook fires when a teammate is about to go idle. The canonical hooks documentation defines generic exit code semantics for all hook events: exit 0 allows the action to proceed, exit 2 blocks the action and feeds the stderr message back to Claude as feedback. Applied to `TeammateIdle`, exit 2 blocks the idle transition — the agent receives the feedback and stays active. Both `remind-unread-advice.sh` and `remind-checkpoint.sh` exit 0 with JSON output. This means the agent is not prevented from going idle. The "no idle hands" principle has no enforcement layer.

**Recommended solution:** Change both scripts to exit 2 when they have something to say. The agent receives the feedback and stays active.

**Alternative:** Keep exit 0 for FYI-level reminders (nothing actionable) and use exit 2 only when there are open OBJECTIONs or uncheckpointed edits. This is softer but still enforces the cases where idling is clearly wrong.

---

### H2 — Unconditional "no idle hands" TeammateIdle hook
**Priority:** 🔴 Critical

**Context:** Even when there are no open advice items and no dirty edits, an agent should not go idle. There is always something productive to do: read ahead, review completed code, check test coverage, investigate unknowns. Currently no hook enforces this — an agent with no pending advice can go idle freely.

**Recommended solution:** New script `enforce-no-idle.sh` that always exits 2 with a concrete directive listing productive alternatives. Registered as a third handler under `TeammateIdle` in `hooks.json`. The message should include specific paths:

```
You have no assigned task. Do not wait idle.
Productive options:
- Check .popcorn-xp/{team-name}/LOG.md for entries you haven't reviewed
- Read ahead into files relevant to upcoming tasks
- Review recently completed code for issues the pair missed
- Check test coverage for the module just touched
- Investigate unknowns noted in LOG.md
```

**Alternative:** Use a `type: "prompt"` hook that asks the model whether the agent has anything left to do and blocks only if the answer is yes. More intelligent but adds latency and token cost on every idle event.

---

### H3 — Fix ID pattern — enforcement is blind to non-standard IDs
**Priority:** 🔴 Critical

**Context:** `check-advice-on-complete.sh` and `remind-unread-advice.sh` both scan for `OBJ-[0-9]+-[0-9]+`. In the `layout-complete` session, the code-reviewer used `REV2-B1` as an OBJECTION ID. The enforcement hook never detected it as a blocking OBJECTION — the pattern didn't match. The OBJECTION was handled manually, not because the hook enforced it. Any advice with a non-standard ID is silently invisible to all enforcement.

**Recommended solution:** Change the grep pattern to match any `### OBJECTION <ID> — open` line regardless of ID format:

```bash
# Before
grep -oE '### OBJECTION (OBJ-[0-9]+-[0-9]+) — open'

# After
grep -oE '### OBJECTION ([^ ]+) — open'
```

Apply the same fix to SMELL/STEER/FYI patterns in `remind-unread-advice.sh`.

**Alternative:** Enforce ID convention strictly — add a `TaskCreated` hook or advice script validator that rejects non-standard IDs at write time. Cleaner long-term but adds friction; the pattern fix is simpler and more robust.

---

### H4 — Case-insensitive resolution matching
**Priority:** 🔴 Critical

**Context:** Both scripts grep for `(FIXED|REJECTED|INCORPORATED|NOTED)` in uppercase. The `layout-complete` session logged resolutions as `### REV2-B1 — fixed` (lowercase). Even if H3 were fixed and the ID matched, the resolution would not be detected — items would appear permanently unresolved. Any agent that writes lowercase outcomes has their resolutions silently ignored.

**Recommended solution:** Add `-i` flag to the resolution grep in both scripts:

```bash
# Before
grep -qE "^### $id — (FIXED|REJECTED|INCORPORATED|NOTED)"

# After
grep -qiE "^### $id — (FIXED|REJECTED|INCORPORATED|NOTED)"
```

**Alternative:** Normalize casing in the `session resolve` script command so outcomes are always written uppercase. Fixes at the source rather than at the reader. Both fixes together are ideal.

---

### H5 — Fix block output channel in `check-advice-on-complete.sh`
**Priority:** 🟠 High

**Context:** The canonical docs specify two distinct output patterns: (a) exit 2 with plain text to stderr for blocking, (b) exit 0 with JSON to stdout for structured decisions. `check-advice-on-complete.sh` sends JSON to stderr with exit 2 — a mix of both patterns. The canonical docs explicitly say "don't mix them: Claude Code ignores JSON when you exit 2." This likely means the feedback content is **fully discarded**, not just rendered as raw JSON. The blocking still works (exit 2 is exit 2), but the reason explaining *why* the task was blocked may be lost entirely — the agent knows it was blocked but not what to fix.

**Recommended solution:** Change the block output to plain text stderr:

```bash
# Before
echo '{"decision":"block","reason":"..."}' >&2
exit 2

# After
echo "X unresolved OBJECTION(s) in .popcorn-xp/$TEAM/ADVICE.md. Engage before completing..." >&2
exit 2
```

**Alternative:** Switch to exit 0 with structured JSON to stdout using the `decision: "block"` format. More structured but adds complexity. Plain text stderr is simpler and correct.

---

## Protocol (`references/protocol.md`)

### P1 — Context limit + handoff pattern
**Priority:** 🟠 High

**Context:** The `layout-complete` retro identified agent degradation after 4-5 tasks. This is almost certainly Sonnet hitting its context window limit (~200K tokens). After 2-3 tasks of pair work — file reads, checkpoint messages, advice exchanges, test output — context fills up and model quality degrades. The current protocol has no mechanism for agents to self-manage this. Agents degrade silently and become unresponsive rather than handing off cleanly.

The session files (LOG.md, ADVICE.md) exist specifically to survive context resets — this is their latent purpose. The missing piece is a protocol for using them as handoff context.

**Recommended solution:** Add a "Context Limit" section to both driver and navigator prompts:

> If you sense your context is getting long (2+ tasks completed, many file reads, conversation history feels large), generate a handoff *before you degrade*. Write `.popcorn-xp/{team-name}/handoff-{your-name}.md` using the handoff format (see Session Files section), then message team-lead: "Context near limit. Handoff written to `.popcorn-xp/{team-name}/handoff-{your-name}.md`. Safe to kill me after I finish this step." Finish your immediate micro-step cleanly, mark task state, then stop. Do not start new work.

**Alternative A:** Instruct agents to run `/compact` proactively before claiming a new task. Simpler — same session, no respawn needed. But compaction summarizes; the handoff is intentional and richer.

**Alternative B:** Have the lead monitor context by tracking task count per agent and proactively respawning after 2 tasks regardless. Removes the judgment call from the agent but requires lead vigilance.

The handoff approach is preferred because: the agent writes it while still coherent, the coordinator retains decision authority, and the fresh agent gets targeted context rather than a compaction summary.

---

### P2 — Handoff format definition
**Priority:** 🟠 High (depends on P1)

**Context:** P1 requires a handoff file format. Without a defined format, agents will write inconsistent handoffs that fresh agents can't reliably parse as a starting prompt.

**Recommended solution:** Add a Handoff format to the Session Files section of `protocol.md`, parallel to the LOG.md and ADVICE.md format definitions:

```markdown
## Handoff — {agent-name}

### Role & Task
[driver/navigator], Task {id}: {task description}
Status: [in_progress — stopped at file:line / just completed]

### What I Was About To Do
[specific next step, file:line if applicable]

### Key Context
- [design decisions made and why — not obvious from the code]
- [tricky parts or gotchas]
- [files to read first for fastest context ramp]

### Open Advice
- [any open OBJECTIONs/SMELLs the new agent should know about]

### Recommended Start
Fresh {role} should: [concrete first action]
```

---

### P3 — `session handoff` command
**Priority:** 🟡 Medium (depends on P1, P2)

**Context:** Agents should write handoffs via the session script for consistency, not via free-form Write tool calls. The session script standardizes the file location and can prepend the template automatically.

**Recommended solution:** Add a `handoff` subcommand to the session script template in SKILL.md Step 2 setup:

```bash
handoff) AGENT="${1:?}"; FILE="$DIR/handoff-$AGENT.md"
  printf '## Handoff — %s\n\n### Role & Task\n\n### What I Was About To Do\n\n### Key Context\n\n### Open Advice\n\n### Recommended Start\n' "$AGENT" > "$FILE"
  echo "Handoff template written to $FILE — fill it out now." ;;
```

Agent calls: `Bash: .popcorn-xp/{team-name}/session handoff {agent-name}`, then edits the file.

**Alternative:** Skip the script command, just instruct agents to write the file directly with the Write tool using the format from P2. Less infrastructure, slightly more prone to inconsistency.

---

### P4 — Run project-native verification before marking complete
**Priority:** 🟠 High

**Context:** The `layout-complete` retro noted that test fixtures written by agents had TypeScript errors (missing `title` field in `FormDefinition`, literal type widening). These were caught during lead QA, not by the agents themselves. Agents completed tasks and marked them done without running any verification commands.

The original proposal hardcoded `tsc --noEmit`, but popcorn-xp is language-agnostic. The principle is: run whatever the project's native build, lint, and type-check tools are before marking a task done. The lead specifies the verification command(s) during setup; agents run them.

**Recommended solution:** Add to driver prompt step 7a (before marking complete):

> Before marking a task complete, run the project's verification commands (build, lint, type-check — whatever the lead specified during setup). Fix any errors before marking done — errors that ship to the next agent become harder to trace.

Add to SKILL.md Step 2 (team setup):

> Identify the project's verification commands (e.g., `tsc --noEmit`, `cargo check`, `ruff check .`, `make lint`) and include them in the team context. Agents must run these before marking any task complete.

Also add to SKILL.md Quality Bar: "Project verification commands pass before any task is marked complete."

---

### P5 — Check messages before claiming a task
**Priority:** 🟢 Low

**Context:** The `layout-complete` retro noted frequent message crossing: agents completing work before receiving assignment messages, leading to duplicate confirmations and confusion about task ownership. Agents were claiming tasks and starting work before checking whether new messages had arrived that changed the picture.

**Recommended solution:** Add to driver prompt step 1:

> Before claiming a task, check your incoming messages. Another agent may have just completed a dependency, sent context, or the lead may have redirected assignments.

---

### P6 — Navigator advice dual-write is mandatory
**Priority:** 🟠 High

**Context:** The `layout-complete` ADVICE.md contained only code-reviewer relay entries. The pair's actual advice — navigator-to-driver observations — lived entirely in ephemeral SendMessage calls and was never persisted. The retro mentioned "craftsman SMELL on NumberPropertyInput" but it doesn't appear in ADVICE.md. When those messages aged out (cap: 50), the advice history was lost. ADVICE.md is supposed to be the persistent record; it functioned instead as a reviewer relay log.

**Recommended solution:** Strengthen navigator prompt step 1c from a reminder to a hard paired action:

> When you send advice via SendMessage, immediately call the session script in the same turn — both happen together, every time:
> ```
> SendMessage(to: "{driver}", ...)
> Bash: .popcorn-xp/{team-name}/session advice SMELL SML-3-01 "description"
> ```
> Do not send advice without logging it. A SendMessage without a session script call means the advice disappears when messages age out.

---

### P7 — Per-edit logging as a numbered sub-step
**Priority:** 🟠 High

**Context:** The `layout-complete` LOG.md had ~10 entries covering 5 phases of work — approximately 2 entries per phase. The protocol says "log after each file edit" but the agents logged at task boundaries instead. The LOG became a task-summary list, not a working record. A fresh agent reading it can reconstruct what was done but not how, what was tried, or what was decided.

The issue is structural: `session log` appears as a note ("Then log it: ...") after the checkpoint description in driver step 5, rather than as a numbered action item. Agents treat it as optional prose.

**Recommended solution:** Split driver prompt step 5 into explicit sub-steps:

> 5. Work in small steps. After EACH file edit, test run, or discovery:
>    - **5a.** Send a checkpoint to your navigator via SendMessage
>    - **5b.** Log it: `Bash: .popcorn-xp/{team-name}/session log "file:line — what you changed, what's next"`
>    
>    Do not batch. One edit = one checkpoint = one log entry. These happen in sequence, not eventually.

---

### P8 — Task headers are mandatory
**Priority:** 🟠 High

**Context:** The `layout-complete` LOG.md had no task headers. The protocol specifies `## Task {id} — Driver @{role}, Navigator @{role}` but agents never wrote them. The result: an undifferentiated checkpoint list with no structure. You cannot tell which checkpoints belong to which task, who was driving, or who was navigating. The LOG is the team's memory — without headers it's a flat stream.

**Recommended solution:** Add a `task` subcommand to the session script:

```bash
task) ID="${1:?}"; DRIVER="${2:?}"; NAV="${3:?}"
  printf '\n## Task %s — Driver @%s, Navigator @%s\n' "$ID" "$DRIVER" "$NAV" >> "$DIR/LOG.md" ;;
```

Add to driver prompt step 2 (immediately after claiming a task):

> Log the task header: `Bash: .popcorn-xp/{team-name}/session task {id} {your-role} {navigator-role}`

---

### P9 — Log advice engagements inline in LOG.md
**Priority:** 🟢 Low

**Context:** When a driver resolves an OBJECTION, they call `session resolve` (writes to ADVICE.md) and send a RESOLVE message. But LOG.md gets no entry. The LOG shows what was built; it doesn't show what was challenged or changed in response to advice. A reader of LOG.md cannot tell that OBJ-3-01 caused a change to the implementation.

**Recommended solution:** Add to driver prompt: when sending a RESOLVE message, also log to LOG.md:

> After calling `session resolve`, also log the engagement:
> `Bash: .popcorn-xp/{team-name}/session log "OBJ-3-01 FIXED: added guard at parser.ts:48"`

---

## SKILL.md (`skills/popcorn-xp/SKILL.md`)

### S1 — Lead handles handoff requests
**Priority:** 🟠 High (depends on P1)

**Context:** P1 adds a handoff protocol for agents near context limit. Without a corresponding instruction for the lead, the handoff message arrives and there's no defined response. The lead needs to know what to do.

**Recommended solution:** Add to Monitor section:

> **Handle handoff requests.** When a teammate sends a context-limit handoff message, read `.popcorn-xp/{team-name}/handoff-{agent-name}.md` immediately. Decide: (a) spawn a fresh agent seeded with the handoff as context, (b) reassign the task to an existing teammate with less context usage, or (c) fold the task if it's close to done. Do not wait for the agent to degrade further — the handoff is most useful when written while the agent is still coherent.

---

### S2 — Plan QA as a fresh agent from the start
**Priority:** 🟡 Medium

**Context:** The `layout-complete` retro noted that the lead had to take over QA because both agents were unresponsive by Task 6. The recommendation was to spawn a fresh agent for QA rather than reusing exhausted ones. This is also a quality argument independent of context exhaustion: QA benefits from genuinely fresh eyes that haven't been involved in the implementation decisions.

**Recommended solution:** Add to Step 3 (Create Tasks) task breakdown guidance:

> QA and late-session verification tasks should be assigned to fresh agents — not agents that drove implementation. Note this in the task description: "Assign to a fresh agent. Do not reuse an agent that has completed 3+ tasks in this session." Plan the fresh spawn in the task breakdown, not as a reactive decision when an agent degrades.

---

### S3 — ID convention for code-reviewer relays
**Priority:** 🟠 High

**Context:** The code-reviewer is an independent agent that produces its own finding IDs (`REV-W1`, `REV2-B1`). When the lead relays these findings to the team, they're logged to ADVICE.md with freeform IDs. The enforcement hooks only recognize `OBJ-[0-9]+-[0-9]+` / `SML-[0-9]+-[0-9]+` patterns (and after H3 is fixed, any `### OBJECTION <ID>` pattern). But beyond hook compatibility, freeform IDs mean the team's advice ledger has two ID conventions mixed together, making it harder to audit.

**Recommended solution:** Add to the Monitor section, Periodic code review bullet:

> When relaying code-reviewer findings to ADVICE.md via the session script, assign standard IDs using the current task number: `OBJ-{task}-{seq}` for blockers, `SML-{task}-{seq}` for warnings. Do not relay the reviewer's internal IDs (e.g. `REV-W1`) — translate them. Example: `session advice OBJECTION OBJ-6-01 "LayoutContainer has no useDroppable"`.

---

### S4 — Open SMELL audit at session close
**Priority:** 🟡 Medium

**Context:** The `layout-complete` session ended with `REV-W1` and `REV-W2` still open in ADVICE.md — both SMELLs about real issues (NumberPropertyInput clear behavior, wrap default mismatch). SMELLs don't block task completion, so they persisted silently. The session close checklist only checks OBJECTIONs. Open SMELLs either become tech debt or get forgotten.

**Recommended solution:** Add to Step 6 close sequence, after confirming no open OBJECTIONs:

> Check ADVICE.md for open SMELLs, STEERs, and FYIs. For each: (a) resolve it now if trivial, (b) create a follow-up task if it warrants future work, or (c) note it in the retro. Do not let the session end with unacknowledged open items — they represent things someone thought were worth raising.

---

### S5 — Parallel scout as default
**Priority:** 🟢 Low

**Context:** The `layout-complete` retro confirmed that running scout research in parallel from session start was effective: "Scout findings were directly usable — no re-exploration needed." The prior retro had recommended this, and it worked. Currently SKILL.md doesn't codify parallel scout as a default — it's described as one option among others.

**Recommended solution:** Add to Step 3 (Create Tasks):

> If task scope is unclear or spans multiple files/areas, create a parallel scout research task with no dependencies alongside the first implementation task. Do not serialize orientation before implementation — plan the full dependency chain upfront and let scout research feed into it concurrently. A scout task that finishes before the implementation task starts is still valuable; a scout task created after implementation has started is largely wasted.

---

### S6 — Two-phase code review as explicit task
**Priority:** 🟢 Low

**Context:** The `layout-complete` retro confirmed the two-phase review pattern worked well: "The final review's BLOCKER was a real runtime bug that would have shipped silently." Currently the Monitor section describes periodic code review as an ad hoc lead action. Scheduling it as an explicit task in the breakdown makes it a hard dependency, not a best-effort action.

**Recommended solution:** Add to the task breakdown template in Step 3:

> For sessions with 4+ implementation tasks, schedule independent code review as explicit tasks with blocking dependencies:
> ```
> Task N:   Code review phases 1-2 — blocked by tasks 1, 2
> Task N+1: Code review phases 3-5 — blocked by tasks 3, 4, 5
> ```
> The reviewer agent is launched independently (no `team_name`) and its findings are relayed by the lead. Planning these as tasks ensures they happen at the right checkpoint, not whenever the lead remembers.

---

### S7 — Reframe task sizing around user value + rotation
**Priority:** 🟡 Medium

**Context:** SKILL.md currently says "Break the work into 3-6 concrete tasks" and warns against "thin verification tasks just to have 4 tasks." This framing optimizes for efficiency and biases leads toward larger tasks. But smaller tasks have a compounding benefit: more rotations, more knowledge distribution, fresher perspectives at each step, and more frequent context handoff opportunities (relevant to P1).

The current "just right" definition ("a function, a test file, or a review") is reasonable but the framing discourages splitting. The right question is user value, not team size.

**Recommended solution:** Replace the current task sizing heuristic with a user-value test:

> **Task sizing:** Each task is the smallest coherent unit that delivers user-observable value. The test: "Could you point to this completed task and say 'the user now has X that they didn't have before'?" If yes, it's a valid task scope. If the deliverable only makes sense as part of something larger, fold it in.
>
> Err toward smaller. More tasks = more rotations = more knowledge distribution. The coordination cost of an extra rotation is low; the cost of one agent driving 3 hours without a perspective change is high.
>
> Examples:
> - "Implement drag-and-drop" → too large; split by observable behavior
> - "Add regression tests for invalid input" → valid, user has proof the case is covered
> - "Read the parser module" → not valid, no deliverable, fold into the first implementation task
> - "Run `tsc --noEmit`" → not valid alone, fold into task exit criteria

Remove the guideline "Don't create thin verification tasks just to have 4 tasks." A verification task forces a rotation and brings fresh eyes — that's a feature.

---

## Agent + Skill Platform (`agents/`, `skills/popcorn-xp/SKILL.md`)

*Findings from canonical subagent and skills documentation.*

### H6 — Verify `systemMessage` vs `additionalContext` in hook output
**Priority:** 🔴 Critical — **resolve before all other hook items**

**Context:** The canonical hooks docs consistently use `additionalContext` as the field name for injecting text into Claude's context from hook JSON output. All current non-blocking hook scripts output `{"systemMessage":"..."}`. If the correct field is `additionalContext`, then every reminder from `remind-unread-advice.sh` and `check-advice-on-complete.sh` is silently discarded — agents never see the SMELL/STEER/FYI nudges. The OBJECTION block (exit 2 + stderr) still works, but the soft enforcement layer doesn't.

**Audit validation (2026-04-02):** Confirmed against canonical hooks documentation. `additionalContext` appears 3 times in the docs; `systemMessage` appears zero times. The docs state: "Text from `additionalContext` is kept from every hook and passed to Claude together." This is almost certainly the correct field name, meaning the entire soft enforcement layer — the part that makes SMELLs, STEERs, and FYIs reach agents — is currently broken. Fix this before H1-H5; those items refine behavior of a channel that may not be delivering anything.

**Recommended solution:** Test by running the hook manually and checking whether the system message appears in a Claude Code session:

```bash
echo '{}' | bash hooks/scripts/remind-unread-advice.sh
```

If the correct field is `additionalContext`, update all non-blocking hook scripts:

```bash
# Before
echo '{"systemMessage":"Popcorn XP: ..."}'

# After
echo '{"additionalContext":"Popcorn XP: ..."}'
```

**Files affected:** `hooks/scripts/remind-unread-advice.sh`, `remind-checkpoint.sh`, `check-advice-on-complete.sh` (warning path), `check-rotation.sh`

---

### H8 — Shell profile echo issue can break JSON output
**Priority:** 🟢 Low

**Context:** When Claude Code runs a hook, it spawns a shell that sources the user's profile (`.zshrc`/`.bashrc`). If the profile has unconditional `echo` statements, that text gets prepended to the hook's stdout — breaking JSON parsing. Users with "Shell ready" or similar debug messages in their profiles will see intermittent JSON validation failures from popcorn-xp hooks.

**Recommended solution:** Add a troubleshooting note to the plugin docs (or hook scripts' headers):

> If hooks error with "JSON validation failed," check `~/.zshrc` or `~/.bashrc` for unconditional echo statements. Wrap them in `if [[ $- == *i* ]]; then ... fi` to suppress them in non-interactive shells.

No change needed to hook scripts themselves — this is a user environment issue.

---

### AT1 — Task status lag: explicit lead check in Monitor section
**Priority:** 🟡 Medium

**Context:** The canonical agent-teams docs list "task status can lag" as a known platform limitation: "Teammates sometimes fail to mark tasks as completed, which blocks dependent tasks." This is distinct from agents becoming unresponsive — the agent may have finished the work but the `TaskUpdate` call silently failed. Dependent tasks won't unblock. The lead has no protocol for this case currently.

**Recommended solution:** Add to SKILL.md Monitor section:

> **Watch for stuck tasks.** If a task appears stuck after a teammate reports it complete, the `TaskUpdate` call may have silently failed (known platform limitation). Check task status directly and update manually if the work is done. Don't wait for the agent to retry — prompt them or update it yourself.

---

### AT2 — Plan approval mode for high-risk tasks
**Priority:** 🟢 Low

**Context:** The agent-teams platform supports requiring plan approval before a teammate begins implementation. The teammate works in read-only plan mode until the lead approves their approach. The lead reviews and either approves (teammate begins implementation) or rejects with feedback (teammate revises). Currently undocumented in popcorn-xp. Relevant for high-risk tasks: schema changes, auth rewrites, API contract changes, anything where a wrong approach is expensive to undo.

**Note:** The canonical docs describe plan approval as a natural language instruction to the lead, not a structured `mode: "plan"` parameter. The invocation is behavioral, not syntactic.

**Recommended solution:** Add to SKILL.md Step 4 (Spawn Teammates) as an optional pattern:

> **For high-risk tasks**, instruct the lead to require plan approval before any edits:
> ```
> Spawn a craftsman teammate for task 5. Require plan approval
> before they make any changes — review their approach before
> they edit anything.
> ```
> The teammate explores and proposes an approach. You review and approve or reject with feedback. Use when a wrong implementation direction would be expensive to undo — schema migrations, auth changes, public API surface changes.

---

### AT3 — Note no-session-resumption limitation and why LOG.md matters
**Priority:** 🟢 Low

**Context:** The canonical docs state: "`/resume` and `/rewind` do not restore in-process teammates. After resuming a session, the lead may attempt to message teammates that no longer exist." If the lead's session crashes or is resumed, the entire team is gone. This is a known platform limitation. LOG.md and ADVICE.md exist precisely to survive this — but the protocol doesn't explicitly say "if you resume a session and teammates are gone, read LOG.md to reconstruct state and spawn fresh agents."

**Recommended solution:** Add a brief note to SKILL.md's Session Files section:

> Session files survive teammate loss. If the session is resumed after a crash or interruption, teammates no longer exist — spawn fresh agents seeded with LOG.md and ADVICE.md to reconstruct state.

---

### R1 — Batch checkpoint allowance for repetitive edits
**Priority:** 🟡 Medium

**Context:** The 2026-04-02 "improvement backlog" retro observed the craftsman batching many edits without checkpoints during Task 3 SKILL.md edits. The protocol says "Do NOT batch multiple file edits into one checkpoint." But for mechanical, repetitive changes — applying the same fix pattern across 4 files, renaming a variable in 6 locations — per-edit checkpoints add noise without value. The navigator doesn't gain new information from "applied the same H3 fix to file 4 of 4."

**Recommended solution:** Add a batch checkpoint exception to driver prompt step 5 in `references/protocol.md` and `skills/popcorn-xp-protocol/SKILL.md`:

> **Batch exception:** For mechanical, repetitive edits — the same pattern applied to multiple files (e.g., fixing the same grep pattern in 4 hook scripts) — you may batch them into one checkpoint. State what you did, how many files, and which ones. This exception does NOT apply when each edit requires judgment or when the files differ structurally.

---

### R2 — Retro instructions in protocol prompts
**Priority:** 🟠 High

**Context:** The 2026-04-02 retro noted "Retro feedback requests went unanswered — both agents kept responding about task status instead of process observations." The retro instructions live in SKILL.md (which agents don't read) and one weak line in `protocol.md` Integration Notes: "the lead *may* ask teammates for retro feedback." S10 auto-loads the protocol via skills, so agents DO read it — but the instruction is buried and optional-sounding.

**Recommended solution:** Add a "Retro" section to the protocol skill (`skills/popcorn-xp-protocol/SKILL.md`) between Rotation and Integration Notes. Make it a named section agents will recognize when the lead asks:

> ## Retro
>
> Before shutdown, the lead asks for retro feedback. When you receive a retro request, respond with **process observations**, not task status:
> - What worked well about the pairing dynamic?
> - What made collaboration harder?
> - Did the advice system help or get in the way?
> - Were checkpoints frequent enough for useful navigation?
> - What would you change about the rotation or task breakdown?
>
> Keep it brief (3-5 sentences). Focus on the process, not the code. "The OBJECTION on depth checking caught a real bug" is useful. "I completed task 3" is not — the lead already knows that from the TaskList.

Also update the Integration Notes line from "the lead *may* ask" to reference the new section.

---

### R3 — Soft checkpoint frequency enforcement via PreToolUse counter
**Priority:** 🟡 Medium

**Context:** The 2026-04-02 retro identified that `remind-checkpoint.sh` only fires on `TeammateIdle`. A driver who keeps editing without going idle (the exact Task 3 failure) never receives a checkpoint reminder. The retro recommends "mechanical enforcement for checkpoint frequency — perhaps a hook that counts edits since last `session log` call."

The canonical hooks docs confirm PreToolUse on Edit/Write can inject `additionalContext` (exit 0 with JSON) without blocking the edit. The existing `mark-dirty.sh` already fires on PreToolUse Edit/Write and uses a flag file. It can be extended to maintain a counter.

**Recommended solution:** Modify `mark-dirty.sh` to:
1. Read stdin to extract `tool_input.file_path`
2. Skip files under `.popcorn-xp/` (session bookkeeping shouldn't count)
3. Increment a counter file (`.popcorn-xp/{team}/.edit-count`) instead of just touching `.dirty`
4. When the counter reaches 3+, output `{"additionalContext": "Popcorn XP: You have N file edits since your last checkpoint. Send a checkpoint to your navigator and log it: .popcorn-xp/{team}/session log 'what you did'"}` to stdout
5. Still exit 0 (soft — doesn't block the edit)

The `session log` command already does `rm -f "$DIR/.dirty"`. Extend it to also `rm -f "$DIR/.edit-count"` to reset the counter.

Update `remind-checkpoint.sh` to also read the counter for its message (so TeammateIdle reminders show the count too).

**Files affected:** `hooks/scripts/mark-dirty.sh`, `hooks/scripts/remind-checkpoint.sh`, `skills/popcorn-xp/SKILL.md` (session script template — add counter reset to `log` subcommand)

---

### AT4 — Canonical docs recommend 5-6 tasks per teammate; S7 recommends smaller tasks
**Priority:** 🟡 Medium (tension to resolve)

**Context:** The canonical agent-teams docs recommend "5-6 tasks per teammate keeps everyone productive." S7 in this backlog recommends smaller tasks sized by user value to encourage more rotation. These pull in opposite directions. The canonical guidance optimizes for throughput (fewer task-switching overhead); S7 optimizes for knowledge distribution (more rotations). The popcorn-xp protocol should explicitly resolve this tension rather than leaving both in play.

**Recommended solution:** The S7 framing should acknowledge the tradeoff:

> Smaller tasks encourage more rotation, which distributes knowledge and brings fresh perspective more often. The platform recommends 5-6 tasks per teammate for throughput — in popcorn-xp, accept a small throughput cost in exchange for more rotations. A 3-task session where both agents drove is better than a 6-task session where one agent drove all of them.

---

### A1 — Set `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` during team setup
**Priority:** 🟡 Medium

**Context:** Subagent auto-compaction defaults to 95% context capacity. By that point agents have been operating near-full for a while and quality has already degraded. This is a direct contributor to the unresponsiveness observed in the retro. The environment variable `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` controls when compaction triggers.

**Recommended solution:** In SKILL.md Step 2 (team setup), set the variable before spawning teammates:

```bash
export CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=70
```

This triggers compaction at 70% rather than 95%, giving agents a clean context window well before degradation. Zero code change, zero protocol change — just an env variable set during setup.

**Alternative:** Leave at default and rely on the handoff pattern (P1) exclusively. Less reliable since agents may not notice degradation before it impacts quality.

---

### A2 — Use `maxTurns` as a mechanical context budget
**Priority:** 🟡 Medium

**Context:** The `maxTurns` frontmatter field limits how many agentic turns a subagent can take before stopping cleanly. After 2-3 tasks of pair work, teammates approach context limits. Rather than relying on agents to self-report (P1) or waiting for degradation, `maxTurns` enforces a hard stop. The stopped agent then triggers the lead to spawn a replacement.

**Recommended solution:** Spawn teammates with an explicit `maxTurns` cap — e.g. `maxTurns: 100`. When the agent hits the limit it stops cleanly. The lead sees the idle notification, reads the current LOG.md state, and spawns a fresh agent seeded with that context. Works as a fallback when agents don't self-initiate the P1 handoff.

**Tradeoffs:** Too low a cap interrupts work unnecessarily. Too high provides no protection. 80-120 turns covers roughly 2-3 tasks of pair work. Should be tuned based on observed session lengths. This complements rather than replaces P1 — P1 is agent-initiated when it notices context growth; `maxTurns` is a mechanical backstop.

---

### A3 — Try SendMessage to resume unresponsive agents before declaring them dead
**Priority:** 🟡 Medium

**Context:** The canonical docs state: "If a stopped subagent receives a SendMessage, it auto-resumes in the background." The retro had agents become unresponsive to task assignments and shutdown requests. The lead's current recovery path is to give up and do the work themselves — which violates the "lead doesn't code" principle. Attempting a SendMessage resume is a free recovery option that wasn't tried.

**Recommended solution:** Add to SKILL.md Monitor section:

> **Recovering unresponsive agents.** Before giving up on a teammate, try sending them a direct message via `SendMessage`. A stopped agent auto-resumes on receipt of a message. If two resume attempts fail, then spawn a fresh replacement seeded with LOG.md context. Do not do the work yourself.

---

### A4 — Add `memory: project` to expert agent only
**Priority:** 🟢 Low

**Context:** Agent definitions support a `memory` frontmatter field that gives each agent a persistent directory surviving across sessions. Teammates currently start every session with no accumulated knowledge of the project. Over time, agents with project memory would build up codebase knowledge — making them increasingly effective on the same codebase.

**Tension with rotation:** Cross-session memory on all agents undermines the fresh-perspective benefit of rotation. A craftsman who remembers "we always structure it this way" from three sessions ago is less likely to challenge the driver's approach. Memory helps with codebase familiarity but works against the "strong opinions, loosely held" principle when spread across all roles.

**Scoping decision:** Only the expert gets `memory: project`. The expert's lens is "does this actually work in edge cases?" — they benefit most from accumulated knowledge of invariants, failure modes, hidden coupling, and codebase quirks that aren't obvious from reading the code cold. The other roles (craftsman, scout, tester) benefit from starting fresh each session.

**What to remember:** The expert's memory should focus on **discovered facts about the codebase** — not user preferences, style opinions, or design decisions. Things worth remembering:
- Invariants that aren't documented ("the parser assumes depth >= 0 but never checks")
- Hidden coupling between modules ("changing X always requires updating Y")
- Test infrastructure quirks ("integration tests require the dev server running")
- File layout patterns ("all validators live in src/validation/, not alongside their consumers")
- Failure modes observed in prior sessions ("this function silently returns null on invalid input")

Things to **not** remember: preferred code style, naming conventions, architectural opinions, user workflow preferences. Those either belong in CLAUDE.md or should be re-evaluated fresh each session.

**Recommended solution:** Add `memory: project` to the expert agent definition only. Include memory instructions:

```markdown
Update your agent memory as you work: note codebase invariants, hidden coupling,
failure modes, test infrastructure quirks, and file layout patterns you discover.
Focus on facts about how the code actually behaves — not opinions about how it
should be structured. Consult your memory before starting work on a familiar codebase.
```

---

### A5 — Navigator "no-edit" enforcement: prompt-only is correct
**Priority:** 🟢 Low — keep as-is

**Context:** The navigator role should never edit code files. Currently this is enforced only by the prompt ("do not edit code files — read and advise only"). There's no mechanical enforcement.

**Why mechanical enforcement doesn't fit:** Agents are long-running and rotate roles between tasks. The craftsman who navigates Task 2 becomes the driver on Task 3. Any static enforcement — `disallowedTools: Edit, Write` in agent frontmatter, `PreToolUse` hooks in agent definitions — would block the agent from editing when it rotates to driver. You'd have to kill and respawn the agent to change permissions, which destroys the accumulated context that makes rotation valuable. This is the core tension: role is dynamic state, agent definitions are static.

**Recommendation:** Keep prompt-only enforcement. The cost of a navigator accidentally editing is low (they'd have to actively go against their role assignment, not just drift), and the cost of mechanical enforcement — either losing context on respawn or maintaining separate agent definitions per role — is high relative to the risk.

---

### S8 — Add `disable-model-invocation: true` to SKILL.md
**Priority:** 🟠 High

**Context:** The popcorn-xp SKILL.md says "Activate when the user explicitly asks" — but this is prose instruction, not frontmatter enforcement. Without `disable-model-invocation: true`, Claude could decide to auto-launch a multi-agent team session when it judges a task warrants one, without the user explicitly requesting it. A team session is expensive (multiple Sonnet instances), disruptive if unexpected, and requires the user's active involvement. It must only fire when explicitly invoked.

**Recommended solution:** Add to SKILL.md frontmatter:

```yaml
disable-model-invocation: true
```

This removes the skill from Claude's auto-invocation consideration entirely. The user must type `/popcorn-xp` or explicitly ask for a team session.

---

### S9 — Dynamic context injection at skill invocation
**Priority:** 🟢 Low

**Context:** When `/popcorn-xp` is invoked on a codebase with a prior session, the lead currently has to manually read LOG.md and RETRO.md to pick up context. The canonical docs show that `!backtick` syntax in SKILL.md runs shell commands before the skill prompt reaches Claude, injecting their output directly. This could auto-inject current session state.

**Recommended solution:** Add dynamic injection to the SKILL.md preamble:

```markdown
## Prior session context
!`[ -f .popcorn-xp/.active-team ] && TEAM=$(cat .popcorn-xp/.active-team) && echo "Active team: $TEAM" && tail -20 .popcorn-xp/$TEAM/LOG.md 2>/dev/null || echo "No active session."`
!`ls .popcorn-xp/*/RETRO.md 2>/dev/null | head -3 | xargs -I{} sh -c 'echo "=== {} ===" && tail -10 {}'  || echo "No prior retros."`
```

The lead immediately has recent LOG context and retro recommendations without a manual read step.

---

### S10 — Preload protocol via `skills` field in agent definitions
**Priority:** 🟢 Low

**Context:** Currently the popcorn-xp protocol is included in each teammate's spawn prompt by the lead copy-pasting from `references/protocol.md`. The canonical docs show that subagent definitions support a `skills` field — the full skill content is injected at startup, not just made available for invocation. This could make the protocol load automatically when a teammate is spawned, without requiring the lead to include it in every spawn prompt.

**Recommended solution:** Extract the protocol content into a `skills/popcorn-xp-protocol/SKILL.md` with `user-invocable: false` (background knowledge, not a command). Add `skills: [popcorn-xp-protocol]` to each popcorn-xp agent definition. The protocol loads automatically; the lead's spawn prompt can focus on role assignment and task context.

**Tradeoff:** Adds coupling between agent definitions and the protocol skill. Changes to the protocol automatically affect all agents, which is good for consistency but requires care during protocol iteration.

---

### N1 — Permission pre-approval as setup step
**Priority:** 🟡 Medium

**Context:** The canonical agent-teams docs warn: "Teammate permission requests bubble up to the lead, which can create friction. Pre-approve common operations in your permission settings before spawning teammates to reduce interruptions." In a multi-agent pair-programming session, permission prompts interrupt flow for both the agent mid-task and the human watching. Long-running agents hit more permission prompts over their lifetime than short-lived subagents — each interruption breaks the driver's editing cadence and the navigator's reading rhythm.

**Recommended solution:** Add to SKILL.md Step 2 (team setup), before spawning teammates:

> **Pre-approve common operations.** Before spawning teammates, ensure your permission settings allow Read, Write, Edit, Bash, and Grep for the project directory without prompting. Teammates inherit the lead's permission settings — pre-approving reduces interruptions during pair work. Check `~/.claude/settings.json` or approve interactively during the first task.

---

### N2 — Team cleanup sequencing in Step 6
**Priority:** 🟡 Medium

**Context:** The canonical agent-teams docs are emphatic: "Always use the lead to clean up. When the lead runs cleanup, it checks for active teammates and fails if any are still running, so shut them down first." The current Step 6 close sequence checks for open OBJECTIONs and presents a summary, but doesn't explicitly sequence teammate shutdown before TeamDelete. If a teammate is still processing when the lead calls TeamDelete, cleanup may fail or leave resources in an inconsistent state.

**Recommended solution:** Make Step 6 close sequence explicit about ordering:

> 1. Confirm all tasks complete and no open OBJECTIONs in ADVICE.md
> 2. Check ADVICE.md for open SMELLs/STEERs/FYIs (see S4)
> 3. Shut down all teammates — send each a message confirming session end, wait for them to stop
> 4. Write RETRO.md
> 5. Present summary to user
> 6. `TeamDelete` to clean up

---

### N3 — Lead-doing-thinking guard in Monitor section
**Priority:** 🟢 Low

**Context:** The canonical agent-teams docs call out a specific failure mode: "Sometimes the lead starts implementing tasks itself instead of waiting for teammates." Coordinator mode prevents the lead from editing files, which handles the literal case. But the subtler version — the lead over-directing, pre-digesting context, synthesizing instead of delegating — is the same orchestrator trap wearing different clothes. The README's "Orchestrator Trap" section describes this philosophy, but the operational Monitor section doesn't guard against it.

**Recommended solution:** Add to SKILL.md Monitor section:

> **Don't fall into the orchestrator trap.** Coordinator mode stops you from editing files, but you can still centralize too much by over-crafting instructions, pre-reading every file for the team, or synthesizing every result before passing it on. If you're spending more time crafting instructions than teammates spend executing them, you're doing their thinking for them. Write the task, assign it, step back. Trust the pair to figure out the approach — that's what the navigator is for.

---

## Summary Table

| ID | Title | Status | Notes |
|----|-------|--------|-------|
| ✅ | No idle hands | Done | protocol.md, SKILL.md, README.md |
| ✅ H6 | `systemMessage` → `additionalContext` | Done | All 4 scripts updated. Stale comments fixed in remind-unread-advice.sh:6 and remind-checkpoint.sh:8. |
| ✅ H1 | TeammateIdle must exit 2 | Done | remind-unread-advice.sh and remind-checkpoint.sh now exit 2 when they have content. |
| ✅ H2 | Unconditional no-idle hook | Done | enforce-no-idle.sh created, registered in hooks.json. Message is generic ("pick something productive") rather than listing specific file paths from the backlog spec. |
| ✅ H3 | Fix ID pattern in enforcement | Done | Applied to check-advice-on-complete.sh, remind-unread-advice.sh, AND check-objections.sh (broader than spec — navigator caught the missing file). Uses `sed` extraction instead of the simpler `([^ ]+)` capture group suggested in backlog. Dead `PREFIX` variables removed during cleanup. |
| ✅ H4 | Case-insensitive resolution matching | Done | `-i` flag added to all resolution greps. Backlog's alternative (normalize to uppercase in `session resolve` command) was NOT applied — only reader-side fix. |
| ✅ H5 | Fix block output channel | Done | Applied to check-advice-on-complete.sh, check-objections.sh, enforce-no-idle.sh, remind-checkpoint.sh, AND check-retro-before-delete.sh (found during doc validation — same JSON-to-stderr bug). All exit-2 paths use plain text stderr. |
| ✅ S8 | `disable-model-invocation: true` | Done | As specified. |
| ✅ P1 | Context limit + handoff | Done | Added "Context Limit" section to both driver and navigator prompts. Handoff file path and format included inline in Session Files section rather than as a separate top-level section. |
| ✅ P2 | Handoff format definition | Done | Placed in driver prompt Session Files section. Format matches spec (5 sections). |
| ✅ P4 | Verification before complete | Done | Driver step 7a updated. SKILL.md Step 2 setup adds verification command identification. Quality Bar updated. |
| ✅ P6 | Advice dual-write mandatory | Done | Navigator step 1c strengthened. "Do not send advice without logging it." |
| ✅ P7 | Per-edit logging as numbered step | Done | Step 5 split into 5a (SendMessage) and 5b (session log). |
| ✅ P8 | Task headers mandatory | Done | Driver step 2 updated. `task` subcommand added to session script template. |
| ✅ S1 | Lead handles handoff requests | Done | Added to Monitor section as specified. |
| ✅ S3 | ID convention for reviewer relays | Done | Added to Monitor periodic code review bullet with example. |
| ✅ N1 | Permission pre-approval | Done | Added to Step 2 setup. |
| ✅ N2 | Team cleanup sequencing | Done | Step 6 reordered: retro (step 4) → shutdown (step 5) → write RETRO.md (step 6) → summary (step 7) → TeamDelete (step 8). |
| ✅ P3 | `session handoff` command | Done | Added to session script template in SKILL.md Step 2. |
| ✅ S2 | Fresh agent for QA | Done | Added to Step 3 task breakdown. |
| ✅ S4 | Open SMELL audit at close | Done | Added as Step 6 item 3 (before retro). |
| ✅ S7 | Task sizing for rotation | Done | Replaced "don't create thin tasks" with user-value test. Includes AT4 tradeoff note inline. |
| ✅ A1 | `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=70` | Done | Added to Step 2 setup with code block. |
| ✅ A2 | `maxTurns` as context budget | Done | Added to Step 4 as prose guidance ("80-120 turns") rather than a hardcoded default. Described as backstop for P1. |
| ✅ A3 | SendMessage resume | Done | Added to Monitor section as specified. |
| ✅ AT1 | Task status lag check | Done | Added to Monitor section as specified. |
| ✅ AT4 | Throughput vs rotation tension | Done | Folded into S7 task sizing paragraph rather than standalone. |
| ✅ P5 | Check messages before claiming | Done | Driver step 1 updated. |
| ✅ P9 | Log advice in LOG.md | Done | Added to driver step 6 (OBJECTION resolution flow). |
| ✅ S5 | Parallel scout as default | Done | Added to Step 3. |
| ✅ S6 | Two-phase review as task | Done | Added to Step 3 with example task dependencies. |
| ✅ N3 | Orchestrator trap guard | Done | Added to Monitor section as specified. |
| ✅ A4 | `memory: project` on expert | Done (prior) | Already in agents/expert.md before this session. |
| ✅ A5 | Navigator no-edit: prompt-only | Done — kept as-is | No change needed. |
| ✅ S9 | Dynamic context injection | Done | Backtick syntax in SKILL.md preamble for active team LOG.md + prior retros. |
| ✅ S10 | Protocol via `skills` field | Done | Created `skills/popcorn-xp-protocol/SKILL.md` with `user-invocable: false`. Added `skills: [popcorn-xp-protocol]` to all 9 agent definitions. Protocol (core rules, advice, formats, rotation) auto-loads at startup. Prompt templates and role blurbs remain in `references/protocol.md` for the lead. |
| ✅ AT2 | Plan approval mode | Done | Added to Step 4 as optional pattern. |
| ✅ AT3 | Session resumption note | Done | Added to Session Files section. |
| ✅ R1 | Batch checkpoint allowance | Done | protocol.md, protocol skill |
| ✅ R2 | Retro instructions in protocol | Done | protocol skill, driver/navigator prompts |
| ✅ R3 | Soft checkpoint frequency enforcement | Done | mark-dirty.sh, remind-checkpoint.sh, session script |
| H8 | Shell profile echo issue | 🟢 Deferred | Docs-only item, no code change needed. |

---

## Post-Implementation

### Doc validation (2026-04-02)

All hook scripts validated against canonical documentation in `research/offical/hooks-ref.md` and `research/offical/hooks-anthro.md`. Findings:

- **check-retro-before-delete.sh**: Had same H5 bug (JSON to stderr with exit 2). Fixed — now uses plain text stderr.
- **`additionalContext` for TaskCompleted**: Not explicitly documented for this event in per-event tables, but mentioned as a context injection field alongside `systemMessage` and plain stdout. Likely works; not confirmed per-event. Monitoring.
- **Dead `matcher: "*"`**: TaskCompleted and TeammateIdle hooks have `matcher` fields that the docs say are silently ignored. Harmless, left in place.
- **Dead `PREFIX` variables**: Removed from remind-unread-advice.sh and check-advice-on-complete.sh after H3 made them unused.
- **Stale comments**: Fixed in remind-unread-advice.sh and remind-checkpoint.sh (said "Non-blocking" and "systemMessage" — now say "Blocking" and reference stderr).

### Test suite (2026-04-02)

Added `tests/test-hooks.sh` — 62 assertions covering all hook scripts:
- No-op behavior (no active session → exit 0)
- H1: exit code semantics for TeammateIdle hooks
- H2: enforce-no-idle always blocks when session active
- H3: flexible ID patterns (non-standard IDs detected)
- H4: case-insensitive resolution matching
- H5: plain text stderr on all exit-2 paths (no JSON)
- H6: `additionalContext` field name (no `systemMessage`)
- Multiple items with partial resolution
- Non-blocking types don't block task completion
- Static output channel consistency check across all scripts
