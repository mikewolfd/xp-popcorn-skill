---
name: popcorn-xp
description: Use when the user explicitly asks for a multi-agent coding session such as "pair program", "xp session", "popcorn", "team of agents", or "work together on this with subagents". Launches an Agent Teams pair-programming session where autonomous teammates coordinate through direct messaging, typed advice with blocking objections, and role rotation.
---

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
| `popcorn-xp:craftsman` | "Is this clean and readable?" | opus |
| `popcorn-xp:expert` | "Does this actually work in edge cases?" | opus (has project memory) |
| `popcorn-xp:tester` | "How will we prove this?" | opus |

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
| `popcorn-xp:code-reviewer` | "What does this code actually do, and can I prove it?" | opus |

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

Use the native agent's `subagent_type` but include the popcorn-xp protocol in the prompt. The native agent definition provides "how I think about this domain"; the protocol provides "how I collaborate in a pair session."

```
Agent(
  name: "test-engineer",
  subagent_type: "test-engineer",
  team_name: "popcorn-xp",
  prompt: "<driver/navigator/advisor template from protocol.md>
           Role: test-engineer (filling tester persona)
           Lens: <use the native agent's own description as the lens>"
)
```

The native agent's behavioral instructions (from its definition file) load automatically via `subagent_type`. Your prompt adds the session protocol on top — the agent gets both its domain expertise AND the collaboration structure.

**What to record:** When writing the team composition in Step 4 of the Workflow, note which personas were filled by native agents and why. This helps the retro assess whether the native agents performed better than defaults would have.

## Workflow

### 1. Understand the Task

Before creating the team, understand the problem yourself. If you have file access, read the relevant code. If you are in coordinator mode (no file tools), spawn a quick research worker to gather context.

**Check for prior retros.** If `.popcorn-xp/RETRO.md` exists, read it. It contains process observations from previous sessions on this codebase — what worked, what didn't, what to change. Apply any relevant recommendations.

Build a mental model of:
- What files are involved
- What the user wants changed
- What could go wrong
- How to verify success

Break the work into 3-6 concrete tasks.

### 2. Create the Team

```
TeamCreate "popcorn-xp"
```

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

### 4. Spawn Teammates

Run the "Discover Native Agents" procedure from the Role Roster section. Then launch 2-3 teammates using the Agent tool with `team_name: "popcorn-xp"`. Give each teammate the protocol from `references/protocol.md` and their role assignment.

For each persona slot, use the native agent if one was discovered, otherwise fall back to the popcorn-xp default. When using a native agent, pass its `subagent_type` so its domain-specific instructions load automatically.

**Example: all defaults (no native agents found)**

```
Agent(
  name: "craftsman",
  team_name: "popcorn-xp",
  prompt: "<driver coordinator prompt from protocol.md>"
)
```

**Example: native agent filling a persona slot**

```
Agent(
  name: "test-engineer",
  subagent_type: "test-engineer",
  team_name: "popcorn-xp",
  prompt: "<driver coordinator prompt from protocol.md>
           Role: test-engineer (filling tester persona)
           Lens: <native agent's description>"
)
```

**Example: mixed team (native + defaults)**

```
# Native flutter-architect fills craftsman for a Flutter project
Agent(name: "flutter-architect", subagent_type: "flutter-architect",
  team_name: "popcorn-xp", prompt: "<driver prompt, lens from native agent>")

# No native expert found — use default
Agent(name: "expert", team_name: "popcorn-xp",
  prompt: "<navigator prompt from protocol.md>")

# Native test-engineer fills tester
Agent(name: "test-engineer", subagent_type: "test-engineer",
  team_name: "popcorn-xp", prompt: "<advisor prompt, lens from native agent>")
```

Assign the first task to the driver via TaskUpdate.

**Reuse orientation agents.** If you spawn a scout or research-focused agent for an initial orientation task, plan a second assignment for them later in the session — test review, demo validation, or a verification task. An agent that goes idle after one task and never returns is wasted capacity. Either give them follow-up work or don't spawn them.

### 5. Monitor

You receive messages from teammates automatically. Your role during execution:

- **Acknowledge completion messages.** When a teammate finishes a task, check TaskList and assign or approve the next task.
- **Steer when needed.** If a teammate is going in the wrong direction, SendMessage with guidance.
- **Relay user input.** If the user provides new instructions, SendMessage to the relevant teammate.
- **Enforce rotation.** When a task completes, swap the driver and navigator roles. The agent that was navigating should drive the next task — they've been watching the code and carry context the other agent doesn't. Resist assigning tasks to the "best-fit" role; rotation is for knowledge sharing, not specialization. **At least one rotation is mandatory per session.** If you reach the final task and the same agent has driven every task, stop and rotate before continuing. A session with no rotation is a solo session with an expensive spectator.
- **Handle escalations.** If the navigator sends an ESCALATION message (the approach is fundamentally wrong), pause the current task, evaluate the concern, and decide whether to redirect, reset, or continue.
- **Periodic code review.** After every 2-3 completed tasks (or after any task that touches shared/critical code), launch `popcorn-xp:code-reviewer` independently — **not** as a teammate. Use the Agent tool without `team_name`. Give it the list of files changed since the last review and ask for a review certificate. When the review comes back:
  - **BLOCKER findings**: relay as OBJECTIONs to the current driver via SendMessage and append to ADVICE.md
  - **WARNING findings**: relay as SMELLs to the driver
  - **NITs/OBSERVATIONs**: note in LOG.md, don't interrupt the driver
  - The code-reviewer never messages teammates directly — you are the relay.
- **Do not do the work yourself.** You are the lead, not a driver. If you find yourself wanting to read a file or write code, delegate it to a teammate instead.

### 6. Verify and Close

When all tasks are complete, follow this sequence exactly. Do not skip steps or reorder — the retro happens **before** the user-facing summary, not after.

1. Ask a teammate (typically the tester) to run final verification.
2. Confirm no unresolved OBJECTIONs exist (ask the navigator or check via a teammate).
3. **Retrospective (mandatory).** Before presenting results to the user, conduct the retro. Ask each active teammate: "What worked well? What would you change about the process? Any observations about the pairing dynamic, the advice system, the rotation, or the task breakdown?" Collect their responses. If teammates have already shut down or are unresponsive, conduct the retro yourself from your observations as lead — you saw every message and every idle notification.
4. Present a technical summary to the user: what was done, what each role found, any remaining risk. Include a brief retro summary (2-3 bullets on what worked, what didn't, what to change next time).
5. Shut down teammates. Send each a shutdown_request individually (broadcast does not support structured messages):
   ```
   SendMessage(to: "craftsman", message: {type: "shutdown_request"})
   SendMessage(to: "expert", message: {type: "shutdown_request"})
   ```
   If a teammate cycles idle without acknowledging the shutdown after 2 attempts, send a plain-text message telling them the session is over and to approve the pending shutdown request. If they still don't respond after a third attempt, move on — they will be cleaned up by TeamDelete.
6. After teammates shut down (or after 3 failed shutdown attempts):
   ```
   TeamDelete
   ```
7. **Write the retro file.** After TeamDelete, write `.popcorn-xp/RETRO.md` with your assessment of the session. This is YOUR perspective as the lead — what you observed about how the team worked, not just what they built. Use the format below.

### Retro File Format

Write `.popcorn-xp/RETRO.md` after every session. This file accumulates across sessions — append a new entry, don't overwrite prior retros.

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

Advice is sent via SendMessage (real-time) and appended to `.popcorn-xp/ADVICE.md` (persistent record).

Three hooks support the advice lifecycle:
- **TaskCompleted** — blocks on open OBJECTIONs, reminds of other open advice
- **TeammateIdle** — reminds the agent of open advice items when they go idle
- **SubagentStop** — backup block on open OBJECTIONs

## Session Files

Three files in `.popcorn-xp/`:

- **LOG.md** — Append-only execution history. What was done, what was learned, what was decided. Written by teammates during the session.
- **ADVICE.md** — Persistent record of all typed advice and resolutions. Written by teammates during the session.
- **RETRO.md** — Accumulated retrospective entries. Written by the lead after each session. Read this before starting the next session — it's the team's process memory.

The first teammate to start work creates `.popcorn-xp/`, LOG.md, and ADVICE.md. The lead creates RETRO.md after TeamDelete.

## Quality Bar

- Only one driver edits at a time. The navigator reads and advises. No concurrent edits.
- OBJECTIONs block task completion. No exceptions.
- Different roles must contribute materially different perspectives.
- Task descriptions carry enough context for independent execution.
- LOG.md is detailed enough that the next agent can reconstruct what happened.
- The lead manages the team but does not do the work.
- Stop spawning rounds when additional tasks stop changing the plan.

## Reference

Read `references/protocol.md` for teammate prompt templates, advice format, and session file templates. Include the relevant protocol sections in teammate prompts when spawning them.
