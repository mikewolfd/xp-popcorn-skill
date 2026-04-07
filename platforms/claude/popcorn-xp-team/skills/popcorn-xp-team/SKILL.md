---
name: popcorn-xp-team
description: "Use when the user explicitly wants Popcorn XP with **native Claude Agent Teams** (coordinator lead, TaskUpdate, SendMessage, context-store hooks). Matches **popcorn-xp-team** plugin. For default file-bus workflow, use **popcorn-xp** plugin + **popcorn-xp** skill."
# disable-model-invocation: true
---

**Transport:** **`popcorn-xp-team`** plugin. Set **`.runtime-mode`** to **`team`**. Enable at most one of **`popcorn-xp`** and **`popcorn-xp-team`** in Claude Code (duplicate hooks if both are on).

## Prior session context

!`[ -f .popcorn-xp/.active-team ] && TEAM=$(cat .popcorn-xp/.active-team) && echo "Active team: $TEAM" && tail -20 .popcorn-xp/$TEAM/LOG.md 2>/dev/null || echo "No active session."`
!`ls .popcorn-xp/*/RETRO.md 2>/dev/null | head -3 | xargs -I{} sh -c 'echo "=== {} ===" && tail -10 {}' || echo "No prior retros."`

# Popcorn XP

Launch an XP pair-programming session using **Agent Teams** transport. You (the lead) run in **coordinator mode** (no direct file tools): create the team, assign tasks with **TaskUpdate**, and coordinate via **SendMessage**. Teammates use the **context store** hooks and native team idle semantics. **Token cost risk:** team mode can inflate context heavily on current Claude Code builds — use only when the user accepts that tradeoff. One **driver** (current), one **navigator** (future), one **advisor** (past); OBJECTIONs still block completion.

**Your lens as lead:** Is the team working effectively? You are not a driver. You set tasks, enforce pairing, relay findings, and intervene on exceptions. Your job is to keep the pair dynamic healthy — rotation, advice flow, checkpoint cadence — not to do the work yourself.

## Trigger

Activate when the user explicitly asks for a team-style workflow:

- "pair program on this"
- "run an XP session"
- "use subagents"
- "let a team of agents work this"
- "popcorn this task" (including "team mode" phrasing — **use this skill only with the `popcorn-xp-team` plugin**; file-bus → **`popcorn-xp`** skill)

Do not activate for ordinary single-agent coding.

### Runtime mode for this plugin

Use **`team`** only (matches **`popcorn-xp-team`** hooks):

```bash
printf '%s\n' team > ".popcorn-xp/$TEAM/.runtime-mode"
```

**Closeout (team):** retro → shutdown → **RETRO.md** → **`check-retro-before-delete`** gates **TeamDelete** → **`cleanup-context-store`**. You may still use **`session`** for LOG/ADVICE/retro subcommands where the playbook references them.

## Role Roster

The plugin ships with agent definitions in `platforms/claude/popcorn-xp-team/agents/` that can be used as teammates. The default team is **3 core members**: **one driver, one navigator, one advisor** - **current, future, and past** respectively. The driver implements what is in flight now; the navigator reads ahead and steers; the advisor reviews what has already landed (verification, regressions, objections). Map concrete personas from `platforms/claude/popcorn-xp-team/agents/` onto those three seats. Add specialists for specific tasks; they are supplemental, not part of the core rotation unless you promote them.

**Core roles (coding tasks):**

| Agent | Lens | Standing work |
|-------|------|--------------|
| `popcorn-xp:craftsman` | "Is this clean and readable?" | Drive and navigate in rotation |
| `popcorn-xp:expert` | "Does this actually work in edge cases?" | Drive and navigate in rotation |
| `popcorn-xp:scout` | "Are we solving the right problem?" | **Default advisor:** log-watching through scope, constraints, and orientation — catch wrong surface, drift, and early unknowns |
| `popcorn-xp:tester` | "How will we prove this works?" | **Usually supplemental:** verification pairs, RED/GREEN lanes, final proof; **standing advisor** only when the session is verification-led |

The **navigator's** standing work is **read-ahead**: stay one step ahead of the driver — read files the driver hasn't reached yet, check constraints and patterns, publish a READY artifact before implementation starts.

The **advisor's** standing work is **log-watching**: read `.popcorn-xp/{team-name}/context-store.log` after every batch of edits, read the changed files through your lens, and send advice. The advisor does not rotate into driving unless they own an explicit task.

**Default the standing advisor to `scout`.** That lens stays on "right problem, right place, right constraints" for the whole session. Use `tester` as standing advisor when tests and proof are the main risk; otherwise pull `tester` in for specific verification tasks or bugfix lanes (see Monitor).

The `scout` agent also fits **orientation-first** work when the first task is "map the codebase" rather than "implement X" (driver or advisor).
The `strategist` agent is for planning-first sessions where the first task is "clarify the bet" rather than "start building."

**Supplemental roles (task-scoped, not part of core rotation):**

| Agent | Lens |
|-------|------|
| `popcorn-xp:strategist` | "Are we building the right thing, for the right people, in the right order?" |
| `popcorn-xp:service-designer` | "Does the interface serve the experience — from API contract to user interaction?" |
| `popcorn-xp:visual-designer` | "Does this look right and feel right?" |
| `popcorn-xp:qa` | "Does this work from the user's perspective?" |
| `popcorn-xp:product-manager` | "What problem are we solving, and is this the right way to solve it?" |

**Independent auditor (not a teammate):**

| Agent | Lens |
|-------|------|
| `popcorn-xp:code-reviewer` | "What does this code actually do, and can I prove it?" |

The code-reviewer is **not** part of the team. Do not spawn it with `team_name`. The lead launches it independently via the Agent tool at review checkpoints (see Monitor section) and relays its findings to the team.

The lens shapes how an agent thinks, not what it's allowed to do. Any teammate can drive, navigate, write tests, or review code. When rotating, prefer giving the driver role to whoever was just navigating — they carry context from watching the code emerge.

### Native Agent Mapping Reference

Native agents carry project-specific context, conventions, and tool configurations that popcorn-xp defaults lack — prefer them when the fit is clear. Use this table when mapping discovered agents to popcorn-xp personas during initialization (Step 2):

| If the agent's purpose is... | It aligns with... |
|---|---|
| Exploring codebases, mapping scope, finding constraints | **scout** |
| Implementing features, refactoring, clean code | **craftsman** |
| Correctness analysis, edge cases, invariants, auditing | **expert** |
| Writing/designing tests, running verification | **tester** |
| Planning, sequencing, positioning, roadmap tradeoffs | **strategist** |
| API design, service boundaries, contracts | **service-designer** |
| UI/UX design, visual patterns, accessibility | **visual-designer** |
| User flow validation, acceptance testing, E2E | **qa** |
| Requirements, prioritization, scope decisions | **product-manager** |
| Independent code review, evidence-based auditing | **code-reviewer** |

A native agent doesn't need to match perfectly — it needs to serve the same lens. A `flutter-architect` can fill the craftsman role for a Flutter project. An `elixir-phoenix-social` can fill the expert role for an Elixir service. A `code-scout` (or similar explore agent) maps to **scout** — **prefer for the standing advisor seat**. A `test-engineer` is a direct replacement for **tester** (verification lens).

**How to spawn — default popcorn-xp agents vs native agents vs plugin agents:**

Default popcorn-xp agents (from the roster tables above) do **not** need `subagent_type` — the plugin registers them and auto-loads the protocol via their `skills` field. Just pass `name` and `model`:

```
Agent(name: "expert", model: "{model}", team_name: "{team-name}", prompt: "...")
```

> **Plugin agent naming (double namespace):** If you do need to pass `subagent_type` for a plugin-registered agent, the format is `popcorn-xp:popcorn-xp:{agent}` — the plugin namespace appears twice (once for the plugin, once from the agent's `name` field which is already prefixed). For example, `subagent_type: "popcorn-xp:popcorn-xp:expert"`. Using the single-namespace form (`popcorn-xp:expert`) will fail to match. In practice, you rarely need this — just omit `subagent_type` for default agents.

**How to spawn a native agent as a teammate:**

Use the native agent's `subagent_type`. The native agent definition provides "how I think about this domain"; the popcorn-xp protocol provides "how I collaborate in a pair session."

Native agents don't have the protocol pre-loaded (only popcorn-xp agents do via the `skills` field). Instruct them to load it as their first action:

```
Agent(
  name: "test-engineer",
  subagent_type: "test-engineer",
  model: "{model}",
  team_name: "{team-name}",
  prompt: "You are a Popcorn XP teammate in session '{team-name}'.

           FIRST: Load the collaboration protocol by invoking:
             Skill('popcorn-xp-protocol')

           Role: test-engineer (filling tester persona)
           Lens: <use the native agent's own description as the lens>

           <driver/navigator/advisor assignment from protocol.md templates>
           <task context>"
)
```

The native agent's behavioral instructions (from its definition file) load automatically via `subagent_type`. The `Skill` invocation loads the collaboration protocol. The prompt adds role assignment and task context.

## Workflow

## Workflow

### 1. Understand the Task

Before creating the team, understand the problem yourself. If you have file access, read the relevant code. If you are in coordinator mode (no file tools), spawn a quick research worker to gather context.

**Check for prior retros.** If `.popcorn-xp/*/RETRO.md` exists for any prior team, read it. It contains process observations from previous sessions on this codebase — what worked, what didn't, what to change. Apply any relevant recommendations.

Build a mental model of:

- What files are involved
- What the user wants changed
- What could go wrong
- How to verify success

State the session goal to the user in one sentence before decomposing: "This session's goal: {what success looks like}." This anchors scope decisions — when a task comes up mid-session, check: does it serve the goal? If not, defer it.

Break the work into 5-8 concrete tasks (run the decomposition checklist in Step 3 on each one).


### 2. Create the Team

**Choose the teammate model.** Ask the user which model to use for teammates:

> What model should I use for the teammates? Options:
>
> - **haiku** — fastest and cheapest, good default for most tasks
> - **sonnet** — more capable, better for complex reasoning
> - **opus** — most capable, slower and more expensive
>
> (Default: haiku)

Store their choice as `{model}` and pass it to every `Agent(model: ...)` call when spawning teammates. If the user doesn't have a preference, default to `haiku`.

**Pick the team.** Scan for available agents, map them to personas, and let the user draft the roster.

**Scan for agents:**

```
Glob("{project}/.claude/agents/*.md")
Glob("{project}/platforms/claude/popcorn-xp-team/agents/*.md")
```

Read the frontmatter (`name`, `description`) of each discovered file. Also review the available `subagent_type` values from the system (these appear in the Agent tool's agent type list). Installed plugins register agents like `test-engineer`, `code-scout`, `flutter-architect`, etc.

**Present what's available.** Show the user all discovered agents alongside the popcorn-xp defaults, mapped to personas using the Native Agent Mapping Reference table. Let the user pick who's on the team:

> Here are the agents available for this session:
>
> | Persona | Available agents |
> |---------|-----------------|
> | scout | `popcorn-xp:scout`, `code-scout` (native) — **default standing advisor** |
> | craftsman | `popcorn-xp:craftsman`, `flutter-architect` (native) |
> | expert | `popcorn-xp:expert` |
> | tester | `popcorn-xp:tester`, `test-engineer` (native) — verification-led advisor or task-scoped proof |
> | strategist | `popcorn-xp:strategist` |
> | code-reviewer | `popcorn-xp:code-reviewer`, `code-reviewer` (native) |
>
> Which roles do you want on the team, and which agent for each? I'll spawn the initial three (driver, navigator, advisor) at the start and bring in supplemental specialists as specific tasks require them. **Unless you prefer a verification-led advisor, default advisor = scout** (or native `code-scout`).

Wait for the user to confirm before proceeding. The user picks:

- Which personas to include (driver, navigator, advisor at minimum; add supplemental specialists as needed)
- Which agent fills each slot (native or default)
- They can also request agents not in the list by name

Not every selected agent is spawned immediately. The lead spawns the initial three-agent team (driver, navigator, advisor) for the first task and brings supplemental specialists in as tasks require them. The full roster is the **bench** — agents the session may use — not a list of agents to launch all at once.

Store the confirmed roster. Note which personas are filled by native agents — this feeds the retro.


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
printf '%s\n' team > ".popcorn-xp/$TEAM/.runtime-mode"
echo "$TEAM" > .popcorn-xp/.active-team
cat > ".popcorn-xp/$TEAM/session" << SCRIPT
#!/bin/bash
exec "$(git rev-parse --show-toplevel)/shared/runtime/bin/session" "\$@"
SCRIPT
chmod 555 ".popcorn-xp/$TEAM/session"
```

This creates `.popcorn-xp/{team-name}/` with fresh LOG.md, ADVICE.md, and a `session` helper that teammates use to append entries. RETRO.md is preserved across sessions.

**Identify verification commands.** Before spawning teammates, identify the project's verification commands (e.g., `tsc --noEmit`, `cargo check`, `ruff check .`, `make lint`) and include them in each teammate's task context. Agents must run these before marking any task complete.

**Set autocompact threshold.** Before spawning teammates, lower the auto-compaction threshold so agents compact before quality degrades:

```bash
export CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=70
```

**Pre-approve common operations.** Before spawning teammates, ensure your permission settings allow Read, Write, Edit, Bash, and Grep for the project directory without prompting. Teammates inherit the lead's permission settings — pre-approving reduces interruptions during pair work. Check `~/.claude/settings.json` or approve interactively during the first task.


### 3. Create Tasks

Every logical task becomes a **pair**: a drive task and a navigate task. This is not optional — solo drivers are a protocol violation. The paired structure makes pairing mechanical: if a drive task has no matching navigate task, the gap is visible in the task list.

**Pair structure:**

```
T{n} drive: "{what to implement}"
             Done when: {one sentence describing how to verify the task is complete}
T{n} nav:   "Navigate T{n} — {what to review, READY scope}"
```

The drive task describes the implementation: what to change, file ownership, exit criteria. The navigate task describes the review scope: what to check, what READY artifact to produce, what risks to watch.

**Task fields** — each drive task should declare:

- `writes`: the files this task may edit
- `reads`: optional files the navigator should stay ahead on

For `ambiguous` tasks (novel design, unclear scope), require a design-alignment handshake before the first edit: the driver states the approach, the navigator responds with a READY artifact, and only then does implementation begin.

**Navigator lifecycle within a pair:**

1. Navigator starts when the drive task is assigned (both tasks are assigned simultaneously)
2. Navigator reads code, publishes READY artifact, sends advice
3. Navigator stays active through the driver's full implementation cycle — sending advice, responding to questions, verifying checkpoints
4. Driver completes their drive task (OBJECTIONs must be resolved)
5. Navigator verifies the final state, then completes their nav task

The navigate task completes AFTER the drive task. This gives the navigator a verification pass on the finished work — exactly the quality gate that solo drivers skip.

**Dependencies between pairs:**

- Drive tasks chain sequentially: T2-drive blocked by T1-drive (no two drivers editing the same codebase simultaneously, unless files are disjoint)
- Navigate tasks are NOT blocked by anything within their pair — the navigator starts when the driver starts
- Navigate tasks for the NEXT pair can start early: T2-nav can read ahead while T1 is still in progress

```
T1 drive: "Add maxDepth parameter to parseBlock()"
           Done when: parseBlock accepts maxDepth and existing callers pass it through.
T1 nav:   "Navigate T1 — review signature threading, check callers"

T2 drive: "Implement depth-exceeded error path" — blocked by T1-drive
           Done when: parseBlock throws DepthExceeded when maxDepth is exceeded.
T2 nav:   "Navigate T2 — review error semantics, check test coverage"

T3 drive: "Add unit tests for valid/invalid depths" — blocked by T2-drive
           Done when: tests cover valid maxDepth, zero, negative, and exceeded cases; all pass.
T3 nav:   "Navigate T3 — verify edge cases, check assertion quality"
```

**Rotation is encoded in the assignments:**

```
T1: craftsman drives, expert navigates
T2: expert drives (was T1 navigator), craftsman navigates (was T1 driver)
T3: craftsman drives (was T2 navigator), expert navigates (was T2 driver)
```

The navigator-becomes-driver pattern is visible in the task assignments, not a soft rule the lead forgets.

**Parallel pairs** work when drive tasks touch disjoint files:

```
T1 drive: "Add drop zone markup"           — writes: src/DropZone.tsx
T1 nav:   "Navigate T1 — review drop zone markup"
T2 drive: "Add drag handlers"              — writes: src/DragSource.tsx
T2 nav:   "Navigate T2 — review drag handler state"
T3 drive: "Integrate drop + drag + state"  — blocked by T1-drive, T2-drive
T3 nav:   "Navigate T3 — verify integration, test drag-drop flow"
```

T1 and T2 run in parallel (disjoint files). Each has its own navigator. T3 depends on both.

**Cap sessions at 20-25 input items.** If the user provides more than 25 items (findings, bugs, features), split into multiple sessions. A single session with 50 items overwhelms the lead — you lose track of agents, fail to enforce pairing, and miss problems mid-session. Run 2-3 focused sessions instead.

**Decompose aggressively.** The most common lead failure is tasks that are too large. A task that takes an agent 30+ turns is almost certainly too big. Target 5-8 logical tasks (10-16 actual tasks with pairs) for any non-trivial session.

**Decomposition checklist — run this on every logical task before creating the pair:**

1. **The "and" test.** If the description contains "and" connecting two distinct actions, split it.
2. **The file test.** If it requires meaningful changes to 3+ files, split by file or layer.
3. **The verb test.** Each task should have one primary verb: implement, test, refactor, validate, review.
4. **The 15-minute test.** If a human pair would spend more than 15 minutes, it's too big.
5. **The description length test.** More than 3-4 sentences to explain = too broad.
6. **The done test.** Can you state in one sentence how to verify this task is complete? If not, the task is underspecified. Write it as `Done when: {criterion}` in the drive task description.

**Split by observable behavior, not by implementation step.** "Implement the happy path" and "implement error handling" are better splits than "write the function" and "wire it up."

Include enough context in each task description for a teammate to execute it independently. State what to do, why it matters, and what success looks like.

**Research and analysis pipelines** often run in parallel. When two agents can gather information independently, model them as concurrent pairs that feed a synthesis pair:

```
T1a drive: "Inventory implementation — components, APIs, constraints"
T1a nav:   "Navigate T1a — verify inventory completeness"
T1b drive: "Read spec — catalog requirements"
T1b nav:   "Navigate T1b — cross-check spec interpretation"
T2 drive:  "Cross-reference: implementation vs. spec" — blocked by T1a-drive, T1b-drive
T2 nav:    "Navigate T2 — verify gap analysis"
```

**For synthesis or authoring tasks,** make expert review an explicit blocking sub-task:

```
T5 drive: "Draft synthesis"
T5 nav:   "Navigate T5 — review draft for completeness"
T6 drive: "Finalize synthesis" — blocked by T5-drive
T6 nav:   "Navigate T6 — final verification pass"
```


**Set up the full dependency chain upfront.** Use `TaskUpdate({ addBlockedBy: [...] })` on drive tasks so they auto-unblock in order. Navigate tasks do not need formal blocking dependencies — they are assigned alongside their paired drive task and the navigator starts immediately.


**Declare file ownership for parallel drive tasks.** If two drive tasks can run in parallel, each must own a disjoint write set. Put the owned files directly in the drive task description. If you cannot name a disjoint write set, the tasks are not really parallel.

**Verification tasks** — when to include as a separate pair:

- A different agent runs verification than wrote the code (fresh eyes)
- Integration or E2E tests that weren't part of the unit test task

When to fold into the last task's exit criteria:

- Same agent would re-run the same tests
- The project is small enough that "run tests" takes seconds

**QA and late-session verification pairs** should be assigned to fresh agents. Note this in the task description: "Assign to a fresh agent." Plan the fresh spawn in the task breakdown, not as a reactive decision.

**If task scope is unclear,** create a parallel scout research pair with no dependencies alongside the first implementation pair.

**For sessions with 4+ implementation pairs,** schedule independent code review as explicit tasks:

```
T-review drive: "Code review T1-T3 changes" — blocked by T1-drive, T2-drive, T3-drive
T-review nav:   "Navigate review — verify findings, check false positives"
```

The reviewer's findings are relayed by the lead as OBJECTIONs or SMELLs to the relevant driver.


### 4. Spawn Teammates

Spawn the initial three-agent team from the roster confirmed in Step 2: one driver, one navigator, and one advisor. All three start simultaneously. The driver and navigator cover the first task pair; the advisor begins log-watching immediately and sends advice from the first checkpoint onward.

You don't need to launch the entire bench on the first task — supplemental specialists join when their task pair is assigned. Pull from the bench when the work calls for a different lens or when rotation calls for a fresh agent.

**Always pass `model: "{model}"` when spawning teammates** (using the model chosen in Step 2), including native agents. Native agent definitions may inherit a different model from their definition file — the explicit `model` parameter overrides that.

For each persona slot, use the agent the user selected in Step 2. When using a native agent, pass its `subagent_type` so its domain-specific instructions load automatically.

**Example: all defaults (no native agents found)**

```
Agent(
  name: "craftsman",
  model: "{model}",
  team_name: "{team-name}",
  prompt: "<driver coordinator prompt from protocol.md>"
)
```

> **Naming reminder:** Default popcorn-xp agents (craftsman, expert, scout, etc.) do not need `subagent_type` — omit it. Native agents use their own name as `subagent_type` (e.g., `"test-engineer"`). If you ever need to reference a plugin agent by type, the format is `popcorn-xp:popcorn-xp:{agent}` (double namespace) — see the Role Roster for details.

**Example: native agent filling a persona slot**

```
Agent(
  name: "test-engineer",
  subagent_type: "test-engineer",
  model: "{model}",
  team_name: "{team-name}",
  prompt: "You are a Popcorn XP teammate in session '{team-name}'.
           FIRST: Load the protocol: Skill('popcorn-xp-protocol')
           Role: test-engineer (filling tester persona)
           Lens: <native agent's description>
           <driver/navigator assignment + task context>"
)
```

**Example: mixed team (native + defaults)**

```
# Native flutter-architect fills craftsman — loads protocol via Skill tool
Agent(name: "flutter-architect", subagent_type: "flutter-architect",
  model: "{model}", team_name: "{team-name}",
  prompt: "FIRST: Skill('popcorn-xp-protocol')\n<driver prompt, lens from native agent>")

# Default expert — protocol auto-loaded via skills field
Agent(name: "expert", model: "{model}", team_name: "{team-name}",
  prompt: "<navigator prompt from protocol.md>")

# Default scout as standing advisor — protocol auto-loaded via skills field
Agent(name: "scout", model: "{model}", team_name: "{team-name}",
  prompt: "<advisor prompt from protocol.md>")

# Or native code-scout as advisor — loads protocol via Skill tool
Agent(name: "code-scout", subagent_type: "code-scout",
  model: "{model}", team_name: "{team-name}",
  prompt: "FIRST: Skill('popcorn-xp-protocol')\n<advisor prompt, lens from native agent>")
```


Assign the first task pair — both the drive task and navigate task — simultaneously. SendMessage both agents with their task metadata:

- Driver: `TaskUpdate(T1-drive, assigned to craftsman)` + SendMessage with:
  `.popcorn-xp/{team-name}/session state {agent} driver driving {task-id} - 'Implement the assigned task and checkpoint after meaningful edits.'`
  `.popcorn-xp/{team-name}/session writeset {agent} {task-id} <owned files...>`
- Navigator: `TaskUpdate(T1-nav, assigned to expert)` + SendMessage with:
  `.popcorn-xp/{team-name}/session state {agent} navigator navigating {task-id} {driver} 'Read the spec/code and publish a READY artifact before edits start.'`

Both agents receive their assignments at the same time. The navigator begins reviewing immediately — they do not wait for the driver to start.

**Reuse orientation agents.** If you spawn a scout or research-focused agent for an initial orientation task, create their follow-up task in Step 3 — not mid-session. A follow-up task added after synthesis has already started arrives as an addendum rather than feeding it. Either plan the second assignment upfront (test review, API audit, demo validation) or don't spawn the agent.

**For high-risk tasks** (schema changes, auth rewrites, public API surface changes), instruct the lead to require plan approval before any edits:

> Spawn a craftsman teammate for task 5. Require plan approval before they make any changes — review their approach before they edit anything.

The teammate explores and proposes an approach. You review and approve or reject with feedback. Use when a wrong implementation direction would be expensive to undo.

**Haiku agents need explicit constraints.** When spawning haiku-model agents, append these lines to every spawn prompt:

```
CONSTRAINTS (haiku model):
- DO NOT create files in .popcorn-xp/ except via the session script
- DO NOT write summary, checkpoint, statistics, or state files
- DO NOT overwrite or edit the session script
- Only modify source code files and use the session script for logging
```

Haiku agents will otherwise create junk files (summaries, ASCII art stats, invented state files) and overwrite the session helper. Opus and sonnet agents follow instructions without these constraints.

**Use maxTurns for haiku agents.** Set `maxTurns: 60` on all haiku-model teammates. This is the only reliable shutdown mechanism for haiku — they resist `{"continue": false}` and loop idle notifications. Opus and sonnet agents respond to shutdown signals correctly and do not need maxTurns unless you want a deliberate lifespan cap.

**Default to long-lived teammates for opus/sonnet.** The point of Popcorn XP is that agents retain session context across multiple tasks and rotations. Replace a teammate when they signal context strain, produce a handoff, or you explicitly want a fresh perspective.

### 5. Monitor

You receive messages from teammates automatically. Your role during execution:

- **Assign pairs, enforce rotation.** When a drive task completes, assign the next pair with roles swapped: the navigator claims the next drive task, the driver claims the next nav task. This is the mechanical rotation — it happens at pair assignment, not as a soft rule. If the same agent has driven two consecutive pairs, you have failed to rotate. Fix it on the next assignment. Do not SendMessage the next assignment until the prior drive task's TaskUpdate confirms completed status — assigning before the TaskUpdate risks the driver abandoning an in-progress task mid-stream.
- **Navigator completes after driver.** When a driver marks their drive task complete, SendMessage the navigator to verify and complete their nav task. The navigator's final action is a verification pass on the finished work. If the navigator finds issues during verification, they send advice (which may include OBJECTIONs that reopen the drive task).
- **Use bugfix lanes when the work is naturally asymmetric.** For bug-driven sessions, prefer `confirm -> RED -> GREEN -> verify` over forcing strict alternation on every pair. Typical split: tester drives confirmation+RED pair, craftsman drives GREEN pair, then a fresh-eye verification pair closes the loop.
- **Steer when needed.** If a teammate is going in the wrong direction, SendMessage with guidance.
- **Unblock, don't observe.** Your job is to remove impediments, not watch progress. When a teammate is stuck, diagnose why and act: split the task, send missing context, reassign, or clarify. Ask yourself: does this task still serve the session goal? If not, defer it.
- **Relay user input.** If the user provides new instructions, SendMessage to the relevant teammate.
- **No idle agents.** If a teammate is not driving, they should be navigating, reviewing, reading ahead, or planning. Require navigators to publish a READY artifact before edits start: risk check, test plan, spec check, or review note. After that, they may enter `waiting_on_driver` explicitly; "silent and maybe thinking" is not a valid state.
- **Handle escalations.** If the navigator sends an ESCALATION message (the approach is fundamentally wrong), pause the current task, evaluate the concern, and decide whether to redirect, reset, or continue.
- **Periodic code review.** After every 2-3 completed tasks (or after any task that touches shared/critical code), launch a **structured reviewer** independently — **not** as a teammate (e.g. **`popcorn-xp:code-reviewer`** when using this plugin’s default agents; otherwise use your project’s review agent). Use the Agent tool without `team_name`. Give it the list of files changed since the last review and ask for a review certificate. When the review comes back:
  - **BLOCKER findings**: relay as OBJECTIONs to the current driver via SendMessage, then run the session script to log it
  - **WARNING findings**: relay as SMELLs to the driver
  - **NITs/OBSERVATIONs**: log via session script, don't interrupt the driver
  - The code-reviewer never messages teammates directly — you are the relay.
  - **When relaying findings to ADVICE.md**, assign standard IDs using the current task number: `OBJ-{task}-{seq}` for blockers, `SML-{task}-{seq}` for warnings. Do not relay the reviewer's internal IDs (e.g. `REV-W1`) — translate them. Example: `session advice OBJECTION OBJ-6-01 "LayoutContainer has no useDroppable"`.
- **Schema violations:** If the project defines schemas (JSON Schema, TypeScript types, Zod, etc.), recommend the team add programmatic validation tests rather than relying on code reviewers to catch structural violations.
- **Keep advisors mechanically active.** If you spawn a long-lived advisor or review-only teammate, schedule a `/loop 3m` prompt that rereads `context-store.log` and the latest touched files. That makes periodic review mechanical instead of depending on the agent to self-start.
  **Note:** The Agent tool may auto-inherit team_name from the lead's session. The
  code-reviewer functions correctly despite this — it does not use SendMessage,
  TaskUpdate, or team coordination tools. Its independence is behavioral (enforced
  by its prompt), not structural.
- **Handle handoff requests.** When a teammate sends a context-limit handoff message, read `.popcorn-xp/{team-name}/handoff-{agent-name}.md` immediately. If they are rotating out after a completed task, also require `.popcorn-xp/{team-name}/snapshot-{agent-name}.md` so the next driver gets touched files, verification run, open advice, and the next risk in one place. If a teammate compacts before stopping, the compaction hooks will persist a summary and `TeammateIdle` will retire them on the next idle once the handoff exists; treat that as a forced handoff, not as normal continuity.
- **Watch for stuck tasks.** If a task appears stuck after a teammate reports it complete, the `TaskUpdate` call may have silently failed (known platform limitation). Check task status directly and update manually if the work is done. Don't wait for the agent to retry — prompt them or update it yourself.
- **Replace agents before they degrade, not after.** When a teammate signals context strain, writes a handoff, or is intentionally running under a `maxTurns` cap, spawn the replacement immediately and assign read-ahead, RED-test prep, or verification work while the current agent still has context. Do not wait for a dead stop before bringing in the next agent.
- **Recovering unresponsive agents.** Before giving up on a teammate, try sending them a direct message via `SendMessage`. A stopped agent auto-resumes on receipt of a message. If two resume attempts fail, spawn a fresh replacement seeded with LOG.md context. Do not do the work yourself.
- **Don't fall into the orchestrator trap.** Coordinator mode stops you from editing files, but you can still centralize too much by over-crafting instructions, pre-reading every file for the team, or synthesizing every result before passing it on. If you're spending more time crafting instructions than teammates spend executing them, you're doing their thinking for them. Write the task, assign it, step back. Trust the pair to figure out the approach — that's what the navigator is for.
- **Do not do the work yourself.** You are the lead, not a driver. If you find yourself wanting to read a file or write code, delegate it to a teammate instead.

### 6. Verify and Close

When all tasks are complete, follow this sequence exactly. Do not skip steps or reorder — the retro conversation happens **before** shutdown, shutdown happens **before** TeamDelete, and the retro file is written **after** shutdown.

1. Ask a teammate (typically the **tester** if on the bench, otherwise the **navigator** or **driver** of the last pair) to run final verification.
2. Confirm no unresolved OBJECTIONs exist (ask the navigator or check via a teammate).
3. **Check ADVICE.md for open SMELLs, STEERs, and FYIs.** For each: (a) resolve it now if trivial, (b) create a follow-up task if it warrants future work, or (c) note it in the retro. Do not let the session end with unacknowledged open items.
4. **Retrospective (mandatory — mechanical).** Run the session retro-request subcommand, then notify each teammate:

   ```bash
   .popcorn-xp/{team-name}/session retro-request
   ```

   ```
   SendMessage(to: "craftsman", summary: "retro time", message: "Retro time. Submit your process observations: .popcorn-xp/{team-name}/session retro craftsman 'What worked? What didn't? What would you change about the process?'")
   ```

   The `enforce-no-idle.sh` hook will nudge any idle teammate automatically. After retro-request, wait for all `.retro-*.md` files before writing RETRO.md. The FileChanged hook will notify you as each one arrives.

   If an agent sends their retro text via SendMessage instead of running the session script themselves, record it on their behalf: `.popcorn-xp/{team-name}/session retro {agent} '{text}'`. This creates the `.retro-{agent}.md` file so the shutdown lifecycle proceeds normally.
5. **Shut down all teammates — explicitly.** Run the shutdown subcommand, then send a shutdown_request to each teammate:

   **Important:** Send a retro request to each agent BEFORE issuing shutdown. The retro-pending phase in `enforce-no-idle.sh` takes priority over shutdown, ensuring agents can write their retro even after `.shutdown` is set. But sending the retro request first gives agents a turn to write while still fully active.

   ```bash
   .popcorn-xp/{team-name}/session shutdown
   ```

   Then send an explicit shutdown_request to each teammate (the hook alone is not sufficient — `{"continue": false}` does not reliably stop agents):

   ```
   SendMessage(to: "craftsman", message: {"type": "shutdown_request"})
   SendMessage(to: "expert", message: {"type": "shutdown_request"})
   ```

   Agents will approve the shutdown_request, which terminates their session. The `enforce-no-idle.sh` hook will also remind any idle agent to approve a pending shutdown_request. Proceed to TeamDelete once all teammates have shut down.
6. **Write the retro file.** After teammates shut down, write `.popcorn-xp/{team-name}/RETRO.md` with your assessment of the session. This is YOUR perspective as the lead — what you observed about how the team worked, not just what they built. Use the format below.
7. **Confirm `RETRO.md` exists before the final user summary.** Do not present the technical summary until `.popcorn-xp/{team-name}/RETRO.md` exists and contains the session entry you just wrote.
8. Present a technical summary to the user: what was done, what each role found, any remaining risk. Include a brief retro summary (2-3 bullets on what worked, what didn't, what to change next time).
9. After teammates have shut down (or after 3 failed shutdown attempts):

   ```
   TeamDelete
   ```

### Retro File Format

Write `.popcorn-xp/{team-name}/RETRO.md` after every session. This file accumulates across sessions — append a new entry, don't overwrite prior retros.

```markdown
# Popcorn XP Retro

## Session: {date} — {task summary}

Session goal: {goal}. Met: yes/no.

- **Lead host:** {`claude-code` | `codex` | other} — which product ran the lead (which hooks and lead playbook applied).
- **Task transport:** {`subagent` | `team`} — should match `.popcorn-xp/{team}/.runtime-mode` when that file exists.

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

Recording **Lead host** and **Task transport** keeps accumulated **RETRO.md** interpretable: process recommendations may reference spawn defaults, hook behavior, or docs that differ between Claude Code and Codex even when **`shared/runtime/bin/session`** behavior is the same.

This file is for the human. Read it before starting the next popcorn-xp session on the same codebase — it's the team's institutional memory about how the process works here.

## Teammate protocol (do not duplicate here)

Typed **OBJECTION** / **SMELL** / **STEER** / **FYI** rules, **ADVICE.md** and **LOG.md** contracts, phase values, advice format, rotation, retro submission, and session file boundaries are defined in **`popcorn-xp-protocol`** (auto-loaded for popcorn-xp agents). The lead’s spawn prompts only need role assignment, names, and task context — plus **`shared/protocol/templates.md`** for long template text.

## Reference

Read **`shared/protocol/templates.md`** for teammate prompt templates and role blurbs. Include the relevant template sections in teammate prompts when spawning them.

## Other transport

- **File-bus / `session task-*`:** **`popcorn-xp`** plugin + **`popcorn-xp`** skill (sibling playbook under **`shared/protocol/lead-playbook/`**).
- **Agent Teams / `TaskUpdate` + `SendMessage`:** **`popcorn-xp-team`** plugin + **`popcorn-xp-team`** skill.
