---
name: popcorn-xp
description: Use when the user explicitly asks for a multi-agent coding session such as "pair program", "xp session", "popcorn", "team of agents", or "work together on this with subagents". Launches an Agent Teams pair-programming session where autonomous teammates coordinate through direct messaging, typed advice with blocking objections, and role rotation.
disable-model-invocation: true
---

## Prior session context
!`[ -f .popcorn-xp/.active-team ] && TEAM=$(cat .popcorn-xp/.active-team) && echo "Active team: $TEAM" && tail -20 .popcorn-xp/$TEAM/LOG.md 2>/dev/null || echo "No active session."`
!`ls .popcorn-xp/*/RETRO.md 2>/dev/null | head -3 | xargs -I{} sh -c 'echo "=== {} ===" && tail -10 {}' || echo "No prior retros."`

# Popcorn XP

Launch an XP pair-programming session. You (the lead) set up the team and step back. Teammates pair-program directly with each other via SendMessage. One driver edits, one navigator steers, they swap roles between tasks. Advice has teeth — OBJECTIONs block task completion.

## Trigger

Activate when the user explicitly asks for a team-style workflow:

- "pair program on this"
- "run an XP session"
- "use subagents"
- "let a team of agents work this"
- "popcorn this task"

Do not activate for ordinary single-agent coding.

## Role Roster

The plugin ships with agent definitions in `agents/` that can be used as teammates. Pick 2-3 agents that match the task. Default to the core four for coding tasks; add specialists when the task calls for them.

**Core roles (coding tasks):**

| Agent | Lens | Model |
|-------|------|-------|
| `popcorn-xp:scout` | "Are we solving the right problem?" | sonnet |
| `popcorn-xp:craftsman` | "Is this clean and readable?" | sonnet |
| `popcorn-xp:expert` | "Does this actually work in edge cases?" | sonnet |
| `popcorn-xp:tester` | "How will we prove this?" | sonnet |

**Specialist roles (when needed):**

| Agent | Lens | Model |
|-------|------|-------|
| `popcorn-xp:service-designer` | "Does the interface serve the experience — API to UI?" | sonnet |
| `popcorn-xp:visual-designer` | "Does this look right and feel right?" | sonnet |
| `popcorn-xp:qa` | "Does this work from the user's perspective?" | sonnet |
| `popcorn-xp:product-manager` | "What problem are we solving, and is this the right way?" | sonnet |

**Independent auditor (not a teammate):**

| Agent | Lens | Model |
|-------|------|-------|
| `popcorn-xp:code-reviewer` | "What does this code actually do, and can I prove it?" | sonnet |

The code-reviewer is **not** part of the team. Do not spawn it with `team_name`. The lead launches it independently via the Agent tool at review checkpoints (see Monitor section) and relays its findings to the team.

The lens shapes how an agent thinks, not what it's allowed to do. Any teammate can drive, navigate, write tests, or review code. When rotating, prefer giving the driver role to whoever was just navigating — they carry context from watching the code emerge.

### Discover Native Agents

Before selecting from the popcorn-xp roster, scan the operating repo and installed plugins for agents that align with the personas you need. Native agents carry project-specific context, conventions, and tool configurations that popcorn-xp defaults lack — prefer them when the fit is clear.

**Step 1 — Scan the repo for local agent definitions:**

```
Glob("{project}/.claude/agents/*.md")
Glob("{project}/agents/*.md")
Glob("{project}/.claude-plugin/agents/*.md")
```

Read the frontmatter (`name`, `description`) of each discovered file. These are custom agents the project has defined.

**Step 2 — Check installed plugin agents:**

Review the available `subagent_type` values from the system (these appear in the Agent tool's agent type list). Installed plugins register agents like `test-engineer`, `code-scout`, `flutter-architect`, `elixir-phoenix-social`, etc. These are already loaded and ready to use.

**Step 3 — Map to popcorn-xp personas:**

For each discovered agent, match it to the popcorn-xp persona whose lens it best serves:

| If the agent's purpose is... | It aligns with... |
|---|---|
| Exploring codebases, mapping scope, finding constraints | **scout** |
| Implementing features, refactoring, clean code | **craftsman** |
| Correctness analysis, edge cases, invariants, auditing | **expert** |
| Writing/designing tests, running verification | **tester** |
| API design, service boundaries, contracts | **service-designer** |
| UI/UX design, visual patterns, accessibility | **visual-designer** |
| User flow validation, acceptance testing, E2E | **qa** |
| Requirements, prioritization, scope decisions | **product-manager** |
| Independent code review, evidence-based auditing | **code-reviewer** |

A native agent doesn't need to match perfectly — it needs to serve the same lens. A `flutter-architect` can fill the craftsman role for a Flutter project. An `elixir-phoenix-social` can fill the expert role for an Elixir service. A `test-engineer` is a direct replacement for tester.

**Step 4 — Select the roster:**

For each persona you need in the session:
1. If a native agent clearly aligns → use it (pass its `subagent_type`)
2. If multiple native agents compete for the same persona → pick the one whose description most closely matches the task at hand
3. If no native agent aligns → fall back to the popcorn-xp default

**How to spawn a native agent as a teammate:**

Use the native agent's `subagent_type`. The native agent definition provides "how I think about this domain"; the popcorn-xp protocol provides "how I collaborate in a pair session."

Native agents don't have the protocol pre-loaded (only popcorn-xp agents do via the `skills` field). Instruct them to load it as their first action:

```
Agent(
  name: "test-engineer",
  subagent_type: "test-engineer",
  model: "sonnet",
  team_name: "{team-name}",
  prompt: "You are a Popcorn XP teammate in session '{team-name}'.

           FIRST: Load the collaboration protocol by invoking:
             Skill('popcorn-xp:popcorn-xp-protocol')

           Role: test-engineer (filling tester persona)
           Lens: <use the native agent's own description as the lens>

           <driver/navigator/advisor assignment from protocol.md templates>
           <task context>"
)
```

The native agent's behavioral instructions (from its definition file) load automatically via `subagent_type`. The `Skill` invocation loads the collaboration protocol. The prompt adds role assignment and task context.

**What to record:** When writing the team composition in Step 4 of the Workflow, note which personas were filled by native agents and why. This helps the retro assess whether the native agents performed better than defaults would have.

## Workflow

### 1. Understand the Task

Before creating the team, understand the problem yourself. If you have file access, read the relevant code. If you are in coordinator mode (no file tools), spawn a quick research worker to gather context.

**Check for prior retros.** If `.popcorn-xp/*/RETRO.md` exists for any prior team, read it. It contains process observations from previous sessions on this codebase — what worked, what didn't, what to change. Apply any relevant recommendations.

Build a mental model of:
- What files are involved
- What the user wants changed
- What could go wrong
- How to verify success

Break the work into 3-6 concrete tasks.

### 2. Create the Team

Choose a short team name that reflects the task (e.g., `fix-parser`, `add-auth`, `refactor-api`).

```
TeamCreate "{team-name}"
```

Set up the session directory (replace `{team-name}` with your chosen name):

```bash
TEAM="{team-name}"
mkdir -p ".popcorn-xp/$TEAM"
echo "# Popcorn XP Log" > ".popcorn-xp/$TEAM/LOG.md"
printf "# Advice\n" > ".popcorn-xp/$TEAM/ADVICE.md"
echo "$TEAM" > .popcorn-xp/.active-team
cat > ".popcorn-xp/$TEAM/session" << 'SCRIPT'
#!/bin/bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
cmd="${1:-}"; [ -z "$cmd" ] && exit 1; shift
case "$cmd" in
  log) printf '\n### Checkpoint\n%s\n' "$*" >> "$DIR/LOG.md"; rm -f "$DIR/.dirty" ;;
  advice) T="${1:?}"; ID="${2:?}"; shift 2; grep -q "^### $T $ID" "$DIR/ADVICE.md" 2>/dev/null && exit 0; printf '\n### %s %s — open\n%s\n' "$T" "$ID" "$*" >> "$DIR/ADVICE.md" ;;
  resolve) ID="${1:?}"; O="${2:?}"; shift 2; printf '\n### %s — %s\n%s\n' "$ID" "$O" "${*:-(no detail)}" >> "$DIR/ADVICE.md" ;;
  task) ID="${1:?}"; DRIVER="${2:?}"; NAV="${3:?}"; printf '\n## Task %s — Driver @%s, Navigator @%s\n' "$ID" "$DRIVER" "$NAV" >> "$DIR/LOG.md" ;;
  handoff) AGENT="${1:?}"; FILE="$DIR/handoff-$AGENT.md"
    printf '## Handoff — %s\n\n### Role & Task\n\n### What I Was About To Do\n\n### Key Context\n\n### Open Advice\n\n### Recommended Start\n' "$AGENT" > "$FILE"
    echo "Handoff template written to $FILE — fill it out now." ;;
esac
SCRIPT
chmod +x ".popcorn-xp/$TEAM/session"
```

This creates `.popcorn-xp/{team-name}/` with fresh LOG.md, ADVICE.md, and a `session` helper that teammates use to append entries. RETRO.md is preserved across sessions.

**Identify verification commands.** Before spawning teammates, identify the project's verification commands (e.g., `tsc --noEmit`, `cargo check`, `ruff check .`, `make lint`) and include them in each teammate's task context. Agents must run these before marking any task complete.

**Set autocompact threshold.** Before spawning teammates, lower the auto-compaction threshold so agents compact before quality degrades:

```bash
export CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=70
```

**Pre-approve common operations.** Before spawning teammates, ensure your permission settings allow Read, Write, Edit, Bash, and Grep for the project directory without prompting. Teammates inherit the lead's permission settings — pre-approving reduces interruptions during pair work. Check `~/.claude/settings.json` or approve interactively during the first task.

### 3. Create Tasks

Use TaskCreate for each work item. Set dependencies with TaskUpdate so tasks unblock in order.

Example task breakdown:
```
Task 1: "Map affected files, entry points, and constraints"
Task 2: "Implement depth validation in parseBlock()" — blocked by 1
Task 3: "Add regression tests for invalid input" — blocked by 2
Task 4: "Run full test suite and verify no regressions" — blocked by 3
```

Include enough context in each task description for a teammate to execute it independently. State what to do, why it matters, and what success looks like.

**Research and analysis pipelines often run in parallel, not series.** When two agents can gather information independently (one reads the implementation, another reads the spec), model them as concurrent tasks that both feed a synthesis task — not a serial chain. Serial chains cause unnecessary idle time when agents could be working in parallel.

Example parallel breakdown:
```
Task 1a: "Inventory implementation — components, APIs, constraints" (no dependencies)
Task 1b: "Read spec — catalog what each section requires" (no dependencies)
Task 2:  "Cross-reference: implementation vs. spec" — blocked by 1a and 1b
Task 3:  "Synthesize findings into prioritized gap list" — blocked by 2
```

**For synthesis or authoring tasks, make expert review an explicit blocking sub-task.** Don't fold it into a note in the task description — review that isn't a hard dependency won't happen until after the synthesis is "done." Use a draft → review → finalize chain:
```
Task Xa: Draft synthesis
Task Xb: Expert reviews draft — blocked by Xa (OBJECTION gate)
Task Xc: Finalize — blocked by Xb
```

**Set up the full dependency chain upfront.** Use `TaskUpdate({ addBlockedBy: [...] })` so tasks auto-unblock as each dependency completes. Teammates self-claim the next unblocked task based on rotation convention (navigator becomes driver), so the chain should reflect the intended execution order. You assign the first task; after that, the normal path flows through built-in task dependencies without your intervention. If you can anticipate auxiliary tasks — an API audit, a renderer compatibility check, a supplementary research pass — create them now. Tasks added mid-session arrive as addenda and feed synthesis less cleanly than tasks planned upfront.

**When to include a separate verification task:**
- A different agent runs verification than wrote the code (fresh eyes)
- Integration or E2E tests that weren't part of the unit test task
- Verification requires a different environment (staging, browser, device)

**When to fold verification into the last task's exit criteria:**
- Same agent would re-run the same tests
- The test-writing task already runs all tests
- The project is small enough that "run tests" takes seconds

**Task sizing:** Each task is the smallest coherent unit that delivers user-observable value. The test: "Could you point to this completed task and say 'the user now has X that they didn't have before'?" If yes, it's a valid task scope. If the deliverable only makes sense as part of something larger, fold it in.

Err toward smaller. More tasks = more rotations = more knowledge distribution. The platform recommends 5-6 tasks per teammate for throughput — in popcorn-xp, accept a small throughput cost in exchange for more rotations. A 3-task session where both agents drove is better than a 6-task session where one agent drove all of them. A verification task forces a rotation and brings fresh eyes — that's a feature.

Examples:
- "Implement drag-and-drop" → too large; split by observable behavior
- "Add regression tests for invalid input" → valid, user has proof the case is covered
- "Read the parser module" → not valid, no deliverable, fold into the first implementation task
- "Run `tsc --noEmit`" → not valid alone, fold into task exit criteria

**QA and late-session verification tasks** should be assigned to fresh agents — not agents that drove implementation. Note this in the task description: "Assign to a fresh agent. Do not reuse an agent that has completed 3+ tasks in this session." Plan the fresh spawn in the task breakdown, not as a reactive decision when an agent degrades.

**If task scope is unclear or spans multiple files/areas,** create a parallel scout research task with no dependencies alongside the first implementation task. Do not serialize orientation before implementation — plan the full dependency chain upfront and let scout research feed into it concurrently. A scout task that finishes before the implementation task starts is still valuable; a scout task created after implementation has started is largely wasted.

**For sessions with 4+ implementation tasks,** schedule independent code review as explicit tasks with blocking dependencies:
```
Task N:   Code review phases 1-2 — blocked by tasks 1, 2
Task N+1: Code review phases 3-5 — blocked by tasks 3, 4, 5
```
The reviewer agent is launched independently (no `team_name`) and its findings are relayed by the lead. Planning these as tasks ensures they happen at the right checkpoint, not whenever the lead remembers.

### 4. Spawn Teammates

Run the "Discover Native Agents" procedure from the Role Roster section. Then launch 2-3 teammates using the Agent tool with `team_name: "{team-name}"`. Give each teammate the protocol from `references/protocol.md` and their role assignment.

**Always pass `model: "sonnet"` when spawning teammates**, including native agents. Native agent definitions may inherit a different model from their definition file — the explicit `model` parameter overrides that.

For each persona slot, use the native agent if one was discovered, otherwise fall back to the popcorn-xp default. When using a native agent, pass its `subagent_type` so its domain-specific instructions load automatically.

**Example: all defaults (no native agents found)**

```
Agent(
  name: "craftsman",
  model: "sonnet",
  team_name: "{team-name}",
  prompt: "<driver coordinator prompt from protocol.md>"
)
```

**Example: native agent filling a persona slot**

```
Agent(
  name: "test-engineer",
  subagent_type: "test-engineer",
  model: "sonnet",
  team_name: "{team-name}",
  prompt: "You are a Popcorn XP teammate in session '{team-name}'.
           FIRST: Load the protocol: Skill('popcorn-xp:popcorn-xp-protocol')
           Role: test-engineer (filling tester persona)
           Lens: <native agent's description>
           <driver/navigator assignment + task context>"
)
```

**Example: mixed team (native + defaults)**

```
# Native flutter-architect fills craftsman — loads protocol via Skill tool
Agent(name: "flutter-architect", subagent_type: "flutter-architect",
  model: "sonnet", team_name: "{team-name}",
  prompt: "FIRST: Skill('popcorn-xp:popcorn-xp-protocol')\n<driver prompt, lens from native agent>")

# Default expert — protocol auto-loaded via skills field
Agent(name: "expert", model: "sonnet", team_name: "{team-name}",
  prompt: "<navigator prompt from protocol.md>")

# Native test-engineer — loads protocol via Skill tool
Agent(name: "test-engineer", subagent_type: "test-engineer",
  model: "sonnet", team_name: "{team-name}",
  prompt: "FIRST: Skill('popcorn-xp:popcorn-xp-protocol')\n<advisor prompt, lens from native agent>")
```

Assign the first task to the driver via TaskUpdate.

**Reuse orientation agents.** If you spawn a scout or research-focused agent for an initial orientation task, create their follow-up task in Step 3 — not mid-session. A follow-up task added after synthesis has already started arrives as an addendum rather than feeding it. Either plan the second assignment upfront (test review, API audit, demo validation) or don't spawn the agent.

**For high-risk tasks** (schema changes, auth rewrites, public API surface changes), instruct the lead to require plan approval before any edits:

> Spawn a craftsman teammate for task 5. Require plan approval before they make any changes — review their approach before they edit anything.

The teammate explores and proposes an approach. You review and approve or reject with feedback. Use when a wrong implementation direction would be expensive to undo.

**Consider spawning teammates with a `maxTurns` cap** (e.g., 80-120 turns) as a mechanical context budget. When an agent hits the limit it stops cleanly — the lead sees the idle notification, reads LOG.md, and spawns a fresh agent seeded with that context. This is a backstop for the P1 handoff pattern: P1 is agent-initiated when the agent notices context growth; `maxTurns` catches the cases where the agent doesn't self-report.

### 5. Monitor

You receive messages from teammates automatically. Your role during execution:

- **Let rotation self-progress.** Teammates self-claim the next unblocked task based on rotation convention: the navigator becomes the driver, the driver becomes the navigator. You set up the dependency chain in Step 3; the platform auto-unblocks tasks and teammates self-claim. Only intervene to override (wrong agent claimed, reorder needed, scope changed) or if self-claim stalls. The check-rotation hook blocks same-agent consecutive driving as a safety net.
- **Steer when needed.** If a teammate is going in the wrong direction, SendMessage with guidance.
- **Relay user input.** If the user provides new instructions, SendMessage to the relevant teammate.
- **Watch for rotation failures.** **At least one rotation is mandatory per session.** If the same agent has driven every task and you're approaching the final task, intervene and force a swap. A session with no rotation is a solo session with an expensive spectator.
- **No idle agents.** If a teammate is not driving, they should be navigating, reviewing, reading ahead, or planning. If you notice a teammate going quiet (no messages, no advice, no file reads), SendMessage them with a specific direction: "Review the files craftsman just changed," "Read ahead into the test files for task 4," "Check test coverage for the module we just touched." An agent that isn't actively contributing is wasting a context window.
- **Handle escalations.** If the navigator sends an ESCALATION message (the approach is fundamentally wrong), pause the current task, evaluate the concern, and decide whether to redirect, reset, or continue.
- **Periodic code review.** After every 2-3 completed tasks (or after any task that touches shared/critical code), launch `popcorn-xp:code-reviewer` independently — **not** as a teammate. Use the Agent tool without `team_name`. Give it the list of files changed since the last review and ask for a review certificate. When the review comes back:
  - **BLOCKER findings**: relay as OBJECTIONs to the current driver via SendMessage, then run the session script to log it
  - **WARNING findings**: relay as SMELLs to the driver
  - **NITs/OBSERVATIONs**: log via session script, don't interrupt the driver
  - The code-reviewer never messages teammates directly — you are the relay.
  - **When relaying findings to ADVICE.md**, assign standard IDs using the current task number: `OBJ-{task}-{seq}` for blockers, `SML-{task}-{seq}` for warnings. Do not relay the reviewer's internal IDs (e.g. `REV-W1`) — translate them. Example: `session advice OBJECTION OBJ-6-01 "LayoutContainer has no useDroppable"`.
  **Note:** The Agent tool may auto-inherit team_name from the lead's session. The
  code-reviewer functions correctly despite this — it does not use SendMessage,
  TaskUpdate, or team coordination tools. Its independence is behavioral (enforced
  by its prompt), not structural.
- **Handle handoff requests.** When a teammate sends a context-limit handoff message, read `.popcorn-xp/{team-name}/handoff-{agent-name}.md` immediately. Decide: (a) spawn a fresh agent seeded with the handoff as context, (b) reassign the task to an existing teammate with less context usage, or (c) fold the task if it's close to done. Do not wait for the agent to degrade further — the handoff is most useful when written while the agent is still coherent.
- **Watch for stuck tasks.** If a task appears stuck after a teammate reports it complete, the `TaskUpdate` call may have silently failed (known platform limitation). Check task status directly and update manually if the work is done. Don't wait for the agent to retry — prompt them or update it yourself.
- **Recovering unresponsive agents.** Before giving up on a teammate, try sending them a direct message via `SendMessage`. A stopped agent auto-resumes on receipt of a message. If two resume attempts fail, spawn a fresh replacement seeded with LOG.md context. Do not do the work yourself.
- **Don't fall into the orchestrator trap.** Coordinator mode stops you from editing files, but you can still centralize too much by over-crafting instructions, pre-reading every file for the team, or synthesizing every result before passing it on. If you're spending more time crafting instructions than teammates spend executing them, you're doing their thinking for them. Write the task, assign it, step back. Trust the pair to figure out the approach — that's what the navigator is for.
- **Do not do the work yourself.** You are the lead, not a driver. If you find yourself wanting to read a file or write code, delegate it to a teammate instead.

### 6. Verify and Close

When all tasks are complete, follow this sequence exactly. Do not skip steps or reorder — the retro conversation happens **before** shutdown, shutdown happens **before** TeamDelete, and the retro file is written **after** shutdown.

1. Ask a teammate (typically the tester) to run final verification.
2. Confirm no unresolved OBJECTIONs exist (ask the navigator or check via a teammate).
3. **Check ADVICE.md for open SMELLs, STEERs, and FYIs.** For each: (a) resolve it now if trivial, (b) create a follow-up task if it warrants future work, or (c) note it in the retro. Do not let the session end with unacknowledged open items.
4. **Retrospective (mandatory).** Before shutting down, conduct the retro with active teammates. Ask each: "What worked well? What would you change about the process? Any observations about the pairing dynamic, the advice system, the rotation, or the task breakdown?" Collect their responses. Teammates must still be alive for this step — do not shut down before asking.
5. **Shut down all teammates** — send each a message confirming session end and wait for them to stop before calling TeamDelete. For each teammate, send a plain-text heads-up followed by the structured request — the plain text primes them to accept:
   ```
   SendMessage(to: "craftsman", summary: "session over", message: "Session is over. Approve the shutdown request that follows.")
   SendMessage(to: "craftsman", message: {type: "shutdown_request"})
   ```
   If a teammate doesn't acknowledge after 2 attempts, move on — TeamDelete cleans up.
6. **Write the retro file.** After teammates shut down, write `.popcorn-xp/{team-name}/RETRO.md` with your assessment of the session. This is YOUR perspective as the lead — what you observed about how the team worked, not just what they built. Use the format below.
7. Present a technical summary to the user: what was done, what each role found, any remaining risk. Include a brief retro summary (2-3 bullets on what worked, what didn't, what to change next time).
8. After teammates have shut down (or after 3 failed shutdown attempts):
   ```
   TeamDelete
   ```

### Retro File Format

Write `.popcorn-xp/{team-name}/RETRO.md` after every session. This file accumulates across sessions — append a new entry, don't overwrite prior retros.

```markdown
# Popcorn XP Retro

## Session: {date} — {task summary}

### Team
- Driver(s): {who drove which tasks}
- Navigator(s): {who navigated which tasks}
- Advisor(s): {if any}
- Native agents used: {list any native agents that filled persona slots, e.g., "test-engineer → tester, flutter-architect → craftsman" — or "none" if all defaults}

### What Worked
- {concrete observation — e.g., "rotation after task 2 gave the expert context they used to catch OBJ-3-01"}
- {concrete observation}

### What Didn't Work
- {concrete observation — e.g., "navigator went idle for 3 checkpoints because checkpoints were too small to analyze"}
- {concrete observation}

### Advice System
- OBJECTIONs raised: {count}
- OBJECTIONs fixed: {count}
- OBJECTIONs rejected: {count}
- SMELLs/STEERs/FYIs: {count}
- Assessment: {did the advice system create the right dynamic? too many objections? too few? did the driver push back enough?}

### Rotation
- {did rotation spread knowledge? did assigning by lens-fit happen despite the protocol? did the navigator-becomes-driver pattern work?}

### Process Observations
- {anything about the protocol itself — too much ceremony? not enough checkpoints? file format issues?}
- {teammate feedback from the retro conversation}

### Recommendations
- {what to change next time — e.g., "start with scout driving orientation before craftsman drives implementation"}
- {what to keep — e.g., "the expert-as-navigator pattern caught 2 real bugs"}
```

This file is for the human. Read it before starting the next popcorn-xp session on the same codebase — it's the team's institutional memory about how the process works here.

## Advice System

Strong opinions, loosely held. The driver has their own approach and should defend it. Advice is input from a different lens — not instructions to follow. The navigator might be wrong. The driver might be wrong. The point is engagement, not compliance.

| Type | Meaning | Driver response | Blocks? |
|------|---------|----------------|---------|
| **OBJECTION** | "This is wrong." | Engage: fix if they're right, reject with reasoning if not. Both valid. | Yes |
| **SMELL** | "This looks off." | Read it. Use your judgment. Acknowledge when you can. | No |
| **STEER** | "Try a different approach." | Consider it honestly. Your way might be better. | No |
| **FYI** | "Noticed this, might matter later." | Noted. | No |

Only OBJECTIONs block task completion. Everything else is the driver's call. The navigator should use OBJECTION sparingly — overusing it makes them a blocker, not a partner.

In research and analysis sessions (no code being written), expect fewer OBJECTIONs — correctness blockers are rare when the output is findings, not a diff. Peer DMs and SMELLs carry most of the coordination in these sessions. That's normal.

Advice is sent via SendMessage (real-time) and appended to `.popcorn-xp/ADVICE.md` (persistent record).

Three hooks support the advice lifecycle:
- **TaskCompleted** — blocks on open OBJECTIONs, reminds of other open advice
- **TeammateIdle** — reminds the agent of open advice items when they go idle
- **SubagentStop** — backup block on open OBJECTIONs

## Session Files

Session files live at `.popcorn-xp/{team-name}/`:

- **LOG.md** — Append-only execution history. Teammates log checkpoints via the `session` script.
- **ADVICE.md** — Append-only advice ledger. Advice and resolutions are both appended; enforcement hooks check for unresolved OBJECTIONs by scanning for IDs without a matching resolution.
- **RETRO.md** — Accumulated retrospective entries. Written by the lead after each session.
- **session** — Helper script teammates call via Bash to append to LOG.md and ADVICE.md.

The lead creates the team directory and files during setup (Step 2). Teammates persist state by calling the `session` script — never by editing files directly. The lead creates RETRO.md after TeamDelete.

**Session files survive teammate loss.** If the session is resumed after a crash or interruption, teammates no longer exist — spawn fresh agents seeded with LOG.md and ADVICE.md to reconstruct state. `/resume` and `/rewind` do not restore in-process teammates.

## Quality Bar

- Only one driver edits at a time. The navigator reads and advises. No concurrent edits.
- OBJECTIONs block task completion. No exceptions.
- Different roles must contribute materially different perspectives.
- Task descriptions carry enough context for independent execution.
- LOG.md is detailed enough that the next agent can reconstruct what happened.
- The lead manages the team but does not do the work.
- No idle agents. Every teammate is either driving, navigating, reviewing, reading ahead, or investigating. An agent with nothing to do should find something — there is always code to review, tests to check, or files to read ahead on.
- Project verification commands pass before any task is marked complete.
- Stop spawning rounds when additional tasks stop changing the plan.

## Reference

Read `references/protocol.md` for teammate prompt templates and role blurbs. Include the relevant template sections in teammate prompts when spawning them.

**Protocol auto-loading:** All popcorn-xp agent definitions include `skills: [popcorn-xp-protocol]`. The full protocol (core rules, advice lifecycle, advice format, session file conventions, rotation rules) is injected into each teammate's context at startup. The lead's spawn prompt only needs role assignment, teammate names, and task context — not protocol copy-paste.
