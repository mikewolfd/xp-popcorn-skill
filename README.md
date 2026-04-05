# Popcorn XP

XP pair programming for Claude Code agents. One driver edits, one navigator steers, they rotate roles, and advice has teeth.

> Claude Code only. This skill depends on Claude Code's Agent Teams and Coordinator Mode features, so it will not run in Codex, Cursor, or other agents.

## What It Does

When you say "popcorn this task" or "run an XP session," the skill launches a pair of Claude Code agents that pair-program on your task. One drives (edits code), one navigates (watches, reads ahead, steers via typed advice), and they swap roles between tasks. Communication is direct — agents message each other in near-real-time without the orchestrator in the loop.

This is pair programming adapted for agents, the same way remote pairing over screen share is pair programming adapted for distributed teams. The navigator can't see live keystrokes — they see checkpoint messages between actions and read the files directly. The feedback loop has the latency of a screen share, not a shared keyboard. But both agents are focused on the same task at the same time, the navigator can block bad code before it ships, and rotation ensures both agents drive and both navigate.

The orchestrator (your main Claude session) sets up the team and steps back. It cannot touch files — it only manages the team lifecycle and relays your instructions. All code work happens inside the teammates.

## How It Works

### The Three Layers

```
You
 │
 ▼
Lead (Coordinator Mode)
 │  Can only: TeamCreate, TaskCreate, Agent, SendMessage, TaskStop
 │  Cannot: Read, Write, Edit, Bash, Grep, Glob
 │
 ├──► craftsman (driver)     ◄──SendMessage──► expert (navigator)
 │    Edits code                               Watches, analyzes, advises
 │    Sends checkpoints                        Sends typed advice
 │    Resolves objections                      Blocks bad code
 │
 └──► tester (advisor, optional)
      Claims verification tasks
      Runs tests
      Sends objections if tests fail
```

**Lead** — Pure orchestrator. Creates the team, breaks the task into work items, spawns teammates, monitors progress, and steers via messages. Has no file access (coordinator mode strips all filesystem tools).

**Teammates** — Autonomous agents with full tool access and direct peer-to-peer messaging. Each has its own 1M token context window. They claim tasks, edit files, message each other, and write to shared session files.

**Micro-tasks** (optional) — Teammates can spawn `claude --bare -p` sub-invocations for focused, disposable sub-work. Useful for constraining a single edit or running a verification command without polluting the coordinator's context. Not required for coordination.

### The Pairing Model

Only one agent drives at a time. This is serial editing with parallel thinking.

- **Driver** — The agent that owns the current active task. Edits code, runs commands, makes changes. Sends checkpoint messages to the navigator after each significant action.
- **Navigator** — Watches the driver via checkpoint messages and by reading files directly. Sends typed advice back. Stays strategic while the driver stays tactical. Proactively steers direction — doesn't just react to checkpoints.
- **Rotation** — Agents swap driver and navigator roles between tasks. The agent that navigated the implementation should drive the next task (verification, hardening, or the next feature chunk) — not because their lens fits best, but because they've been watching the code emerge and now carry context the other agent doesn't have. This is the XP principle: rotation spreads knowledge, not optimizes for specialization.

No worktrees. No merge conflicts. One driver at a time means one writer at a time.

**No idle hands.** Serial editing does not mean serial thinking. While the driver edits, the navigator reads ahead, reviews the driver's changes, checks test coverage, and investigates unknowns. Between tasks, the transitioning agents immediately pick up navigator duties — reviewing their own changes from the outside, exploring files relevant to the next task, or checking for issues the pair missed. An agent that isn't driving should be actively contributing through a different channel, not waiting for assignment.

**Soft lock awareness.** The context store tracks which agent last edited each file and marks files dirty when edits are in progress. When the navigator reads a file the driver is editing, the store injects cache metadata ("expert is actively editing this — since 2:15pm"). This is awareness, not enforcement — the navigator reads anyway, but knows the file is hot. This is how pair programming survives the medium latency: the navigator's "watch the driver work" becomes "watch the shared store for activity," and STEER advice flows based on what the store shows is happening.

**The medium constraint:** The navigator sees checkpoint messages and reads files, not live keystrokes. This is the same class of limitation as screen-share latency in remote pairing — a constraint of the medium, not a change in the dynamic. Both agents are focused on the same work at the same time. The navigator proactively reads ahead and steers. The driver receives advice between actions and must engage with OBJECTIONs before completing. It's pair programming with the latency of a remote session.

### Typed Advice With Teeth

Advice is input, not instructions. The driver has their own approach and should defend it. But advice needs weight — without it, every suggestion gets ignored.

The type system creates a gradient of engagement, not a gradient of compliance:

| Type | Meaning | Driver response | Blocks? |
|------|---------|----------------|---------|
| **OBJECTION** | "This is wrong." | Engage: fix if right, reject with reasoning if not. Both valid. | Yes |
| **SMELL** | "This looks off." | Read it. Use your judgment. | No |
| **STEER** | "Try a different approach." | Consider honestly. Your way might be better. | No |
| **FYI** | "Noticed this, might matter later." | Noted. | No |

Advice travels via SendMessage (real-time, auto-delivered) and is also appended to `ADVICE.md` (persistent record). Messages are ephemeral and capped at 50 per agent; the file is the durable history.

**Only OBJECTIONs block.** The driver cannot complete a task with an unresolved OBJECTION. They must engage — fix the issue OR reject with their reasoning. Rejection with good reasoning is a valid outcome. The point is engagement, not agreement.

The navigator should hold their opinions loosely too. Not every concern is an OBJECTION. Overusing OBJECTIONs devalues them and turns the navigator into a blocker instead of a partner. Use OBJECTION when something is genuinely wrong — a correctness issue, a missed requirement, a bug that will ship. Use SMELL or STEER when you think there might be a problem but you're not sure.

Example:
```
@expert → @craftsman via SendMessage:

OBJECTION OBJ-2-01: parseBlock() silently swallows errors when depth < 0.
File: src/parser.ts:47
Evidence: Tested with ')))}' — no error thrown, returns empty AST.
Required: Add depth check before recursion.
You must resolve this before completing your task.
```

### Task Ownership Replaces LOCK.md

There is no LOCK.md. The native shared TaskList tracks who is working on what:

```
Task 1: "Map affected files and entry points"       → owner: scout, status: completed
Task 2: "Add depth validation to parseBlock()"      → owner: craftsman, status: in_progress
Task 3: "Verify parser test suite still passes"     → owner: (unclaimed), status: pending, blocked by: 2
Task 4: "Add regression tests for invalid input"    → owner: (unclaimed), status: pending, blocked by: 3
```

The driver is whoever owns the current `in_progress` task. Driver rotation = the next task gets claimed by a different role. The lead manages assignment via TaskUpdate, or teammates self-claim from the queue.

### Session Files

Only two files, both written by teammates (the lead cannot write files):

```
.popcorn-xp/
├── LOG.md      — Append-only execution history with checkpoints
├── ADVICE.md   — Persistent record of typed advice and resolutions
└── RETRO.md    — Accumulated retrospectives from each session (written by lead)
```

**LOG.md** — What happened. One line per checkpoint. Enough that the next driver can pick up where you left off.

```markdown
## Task 2 — Driver @craftsman, Navigator @expert

### Checkpoint 1
Split parseRepeatBlock into validate + parse in src/parser.ts:47. Depth tracking unchanged. Acknowledged SML-2-01 (error format — keeping it, consistent with other parser errors).

### Checkpoint 2
OBJ-2-01 from @expert: depth < 0 not guarded. They're right — fixing.

### Checkpoint 3
Added depth < 0 guard to src/parser.ts:48. OBJ-2-01 FIXED. Added 2 regression tests. 12/12 green.

### Task Complete
Parser rejects unmatched endRepeat, depth validated, tests green. Next: @tester drives verification.
```

**ADVICE.md** — The persistent record of all advice, mirroring what was sent via SendMessage.

```markdown
# Popcorn XP Advice

## Open

(none)

## Resolved

### OBJECTION OBJ-2-01 — from @expert to @craftsman
- Task: 2
- File: src/parser.ts:47
- Issue: parseBlock silently swallows error when depth < 0
- Evidence: Tested with ')))}' — no error, returns empty AST
- Suggested action: Add depth check before recursion
- Status: resolved
- Resolution: Fixed in checkpoint 3 — added guard for negative depth
```

## Setup

### Requirements

- Claude Code v2.1.32+
- Claude Code build with Coordinator Mode available
- Opus 4.6 model

### Recommended: tmux for Live Visibility

Running inside tmux gives each teammate its own pane — you can watch the driver edit and the navigator read in real time, side by side. This is the closest experience to watching a real pair.

```bash
tmux new-session -s claude
# then launch claude code inside the session
```

Without tmux (in-process backend), teammates run in the background and you only see the results. iTerm2 with the `it2` CLI also works for split-pane visibility on macOS.

### Enable Required Claude Code Flags

Add to `~/.claude/settings.json`:

```json
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1",
    "CLAUDE_CODE_COORDINATOR_MODE": "1"
  }
}
```

Restart Claude Code after editing.

`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` enables the Agent Teams feature. `CLAUDE_CODE_COORDINATOR_MODE` forces the lead into coordinator mode so it cannot fall back to direct file edits. If your Claude Code build does not include coordinator mode support, the env var alone will not enable it.

### Install the Skill

Install from the repository with `npx skills`:

```bash
npx skills add https://github.com/mikewolfd/xp-popcorn-skill --skill popcorn-xp
```

To install from a local checkout instead:

```bash
npx skills add /path/to/xp-popcorn-skill --skill popcorn-xp
```

The `npx skills` install path is just distribution. Runtime is still Claude Code only.

## Usage

Trigger with natural language:

- "popcorn this task"
- "pair program on this"
- "run an XP session"
- "use a team of agents to work on this"
- "let agents work together on this"

The skill activates, the lead creates the team, and you watch them work. You can steer any teammate directly by addressing them by name.

## Role Roster

The skill defaults to 2-3 agents. Each has a lens — a default perspective they bring — but the lens does not determine what they do. Any agent can drive, navigate, write tests, or review code. The lens shapes how they think about the work, not what work they're allowed to do.

| Role | Lens | Default perspective |
|------|------|---------------------|
| **scout** | "Are we solving the right problem?" | Scope, constraints, unknowns |
| **craftsman** | "Is this clean and readable?" | Implementation shape, naming, boundaries |
| **expert** | "Does this actually work in edge cases?" | Invariants, failure modes, hidden coupling |
| **tester** | "How will we prove this?" | Test strategy, regressions, verification gaps |
| **strategist** | "Are we building the right thing, for the right people, in the right order?" | Planning, sequencing, positioning, roadmap tradeoffs |

The lens is a starting point for analysis, not a job description. When the expert drives an implementation task, they bring a correctness lens to the code they write. When the craftsman navigates a verification task, they bring a readability lens to the test review. When the strategist is present, they keep the team honest about sequencing, positioning, and whether the work still serves the intended market. Rotation works because every agent can do every job — the lens just means they'll notice different things.

The strategist is especially useful when the session starts with planning or positioning instead of implementation.
It is usually a supplemental lens, not part of the core driver/navigator/tester rotation.

## Workflow Detail

### 1. Lead Setup

The lead (your main session, in coordinator mode) does:

1. Reads the task and relevant code (via a worker if needed)
2. `TeamCreate "popcorn-xp"`
3. `TaskCreate` for each checklist item, with dependencies
4. Spawns 2-3 teammates via `Agent` with `team_name: "popcorn-xp"`
5. Assigns the first task

### 2. Driver Works

The driver teammate:

1. Claims or receives a task from the TaskList
2. Reads relevant files, understands the problem
3. Edits code, runs commands
4. After each significant action, sends a checkpoint message to the navigator
5. Checks incoming messages — if OBJECTION received, resolves before continuing
6. Appends checkpoint to LOG.md
7. Marks task complete when done
8. Checks TaskList for next available task, or goes idle

### 3. Navigator Steers

The navigator teammate:

1. Receives checkpoint messages from the driver (auto-delivered, no polling)
2. Reads the files the driver mentioned — and other files they think are relevant
3. Analyzes through their lens, but also proactively steers direction:
   - "Before you edit that function, read lines 80-95 — there's a constraint you'll hit"
   - "The approach in file X is simpler, consider adapting it"
   - "Skip the refactor — the existing shape handles this case already"
4. Sends typed advice via SendMessage (OBJECTION / SMELL / STEER / FYI)
5. Appends the same advice to ADVICE.md for persistence
6. Between checkpoints, continues reading ahead — exploring files the driver hasn't reached yet, anticipating the next problem, and sending STEER advice to shape the approach before the driver commits to it

### 4. Rotation

When a task completes, the driver and navigator swap roles for the next task. Rotation is self-driven using built-in task dependencies — the lead sets up the dependency chain, the platform auto-unblocks tasks, and teammates self-claim based on rotation convention:
- The agent that was navigating self-claims the next unblocked task and becomes the driver. They've been watching the code emerge and carry context the other agent doesn't have.
- The agent that was driving sends a handoff message (what changed, what's tricky) and becomes the navigator. They know what they just did and can catch the new driver's misunderstandings.
- The lead intervenes only on exceptions — wrong agent claimed, reorder needed, scope changed. The check-rotation hook blocks same-agent consecutive driving as a safety net.
- If a third agent (advisor) is present, the lead may rotate them into the pair.

Rotation is for knowledge sharing, not for matching roles to tasks. Resist the urge to assign the "implementation task" to the craftsman and the "testing task" to the tester. The craftsman who navigated the implementation should drive the tests — they'll catch things the tester won't.

### 5. Completion

When all tasks are done:
- The lead spawns a verification teammate (or asks the tester) to run final checks
- The lead confirms no unresolved OBJECTIONs in ADVICE.md
- The lead presents a summary to the user
- `TeamDelete` to clean up

## Why This Architecture

### The Orchestrator Trap

The default pattern for multi-agent systems is hub-and-spoke: one orchestrator dispatches work, collects results, synthesizes, dispatches again. It's intuitive because it mirrors how we think about management — one brain coordinates many hands.

The problem is that the orchestrator becomes the bottleneck. It does all the thinking between rounds. It decides what each agent should do, pre-digests context for them, and interprets their results. The agents aren't collaborating — they're answering questions posed by a central authority. Call this a "batch query with extra steps."

In real pair programming, there is no orchestrator. Two people sit at one keyboard. One types. The other watches, challenges, and steers. They talk directly to each other. Nobody mediates.

Popcorn XP enforces this by making the lead structurally unable to do the work. Coordinator mode strips all file tools from the lead — no Read, Write, Edit, Bash. The only way to get anything done is through the team. This isn't a limitation imposed by the platform; it's the design. The lead that can't touch files can't fall back to doing everything itself.

### Peers, Not Workers

There are two models for multi-agent coordination in Claude Code, and they reflect fundamentally different philosophies.

**Coordinator Mode workers** report to the coordinator and cannot message each other. All inter-worker communication routes through the hub. This is a command-and-control topology — efficient for fan-out/fan-in tasks where the coordinator synthesizes.

**Agent Teams teammates** message each other directly. The navigator sends an objection to the driver without the lead involved. The driver responds. The lead sees a summary but doesn't mediate every exchange.

XP pairing requires the second model. The navigator's value comes from real-time feedback during the driver's work, not from a post-hoc review that the orchestrator relays. When the expert spots a bug mid-edit, the message needs to reach the craftsman now — not after the round ends and the orchestrator reads the results.

### One Writer at a Time

Most multi-agent architectures assume parallel editing. Multiple agents work on different files simultaneously, coordinate through git, and resolve merge conflicts. This requires worktrees, branch strategies, and conflict resolution — significant complexity.

XP pair programming has one driver at a time. The navigator reads and thinks in parallel with the driver, but only the driver edits. This is serial editing with parallel thinking.

The navigator in Popcorn XP sees checkpoint messages between the driver's actions and reads the same files directly — similar to watching a screen share with slight lag. They proactively read ahead into files the driver hasn't reached yet and send STEER advice to shape the approach before the driver commits. OBJECTIONs block the driver from completing the task, forcing engagement with the navigator's feedback.

The feedback latency is real but small. Messages auto-deliver between tool calls. The driver checks messages after each action. In practice, the navigator's advice arrives within seconds of the checkpoint that triggered it — comparable to the lag in a remote pairing session over video call.

No worktrees. No merge conflicts. No git coordination overhead. The constraint is the feature.

### Strong Opinions, Loosely Held

In real pair programming, both people have opinions. The driver has an approach they believe in. The navigator has a different perspective. The conversation between them — "I think X," "but what about Y," "good point, but Z" — is where the value comes from. Neither person is executing the other's instructions. They're both thinking.

LLM agents default to compliance. Tell an agent "you should consider error handling" and it will add error handling, whether or not it was needed. There's no internal judgment filter that says "actually, my approach handles this already." Without that filter, advice becomes instructions and the navigator becomes a micromanager.

The typed advice system recreates the pair programming dynamic by giving advice weight (so it can't be silently ignored) while preserving driver autonomy (so the driver isn't just executing the navigator's todo list):

**OBJECTION** is the navigator saying "stop — I think this is wrong." It blocks task completion. But the driver can reject it with reasoning: "No, because the upstream validation already handles this case." A rejection with good reasoning is a valid outcome. The point is engagement — the driver must think about the concern, not automatically fix it.

**SMELL** is "this looks off to me." The driver should read it. They might agree and adjust, or they might know something the navigator doesn't: "That looks redundant but it handles the edge case where X." No enforcement — it's the driver's call.

**STEER** is "have you considered this approach?" The driver might have a better reason for their approach: "I thought about that, but the current shape handles the migration path." Or the navigator might be right: "Good point, switching to that." Either way, the driver decides.

**FYI** is context. Noted and moved on.

The enforcement gradient is deliberately narrow: only OBJECTIONs block. This prevents the navigator from accumulating soft power through a pile of SMELLs and STEERs that collectively pressure the driver into compliance. The driver should feel free to dismiss advice when they have good reason — and the navigator should be OK with that, because the system worked: the concern was raised, considered, and decided.

The gradient from FYI to OBJECTION mirrors how pair programming feedback actually works. Most feedback is lightweight. Some needs engagement. Occasionally, something is wrong enough to stop the work. Without this gradient, you get either a toothless suggestion box (everything is a suggestion) or an adversarial veto system (everything is a block). The type system finds the balance.

### Every Piece of Advice Matters

The original design focused enforcement on OBJECTIONs — the navigator's "stop, that's wrong." But a STEER that gets ignored means the driver missed a better approach. An FYI that's never read means context was lost. A SMELL that's unacknowledged means a potential issue went unexamined.

All advice has a lifecycle: created, delivered, persisted, read, considered, resolved. The type determines the enforcement level — how hard the system pushes for engagement — not whether the advice matters.

```
Created → Delivered → Persisted → Read → Considered → Resolved
  (nav)    (SendMsg)  (ADVICE.md)  (driver)            (driver writes resolution)
```

Four types of hooks enforce coordination state:

**Advice Lifecycle** — Two hooks ensure advice is surfaced and engaged with:

- **TaskCompleted** — fires when a teammate marks a task done. This is the primary enforcement point. The hook reads ADVICE.md and:
  - Blocks on open OBJECTIONs (must fix or reject with reason)
  - Reminds on open SMELLs, STEERs, and FYIs (read them and decide; they do not block)

- **TeammateIdle** — fires when a teammate goes idle between turns. The hook reads ADVICE.md and reminds the agent of all open items, prompting them to check the file and resume active work. Agents should not stay idle — the hook nudges them back into reviewing, reading ahead, or investigating.

Both are no-ops when `.popcorn-xp/ADVICE.md` doesn't exist — no active session means no enforcement.

**Context Store (Soft Lock)** — Two hooks track file edits and warn of conflicts:

- **PreToolUse(Read)** — On every file read, checks the shared context store. If the file was recently edited by another agent, injects metadata: "expert edited this 2 minutes ago." Allows the read but provides awareness.
- **PreToolUse(Edit/Write)** — On every edit, marks the file dirty in the store and records the current editor. If another agent had it dirty, emits a soft lock warning: "craftsman is actively editing this." Allows the edit to proceed (no blocking), but prevents accidental clobbering through visibility.

The context store creates a shared index of file activity — who read what, when, and whether it has unsaved edits. Hooks are no-ops when no active session; the store is populated only during team sessions.

The enforcement gradient:

| Type | TaskCompleted | TeammateIdle |
|------|--------------|-------------|
| OBJECTION | Block | Remind |
| SMELL | Remind | Remind |
| STEER | Remind | Remind |
| FYI | Remind | Remind |

This ensures that even low-severity advice gets surfaced. An FYI doesn't block your task, but the TeammateIdle hook will keep reminding you it's there until you mark it as noted. The cost of resolving an FYI is one line in ADVICE.md. The cost of ignoring it might be missing context that matters three tasks later.

### The Advice File as Shared Memory

ADVICE.md isn't just a record of objections. It's the team's shared memory — the persistent record of everything one agent noticed that another should know about. Messages are ephemeral (capped at 50 per agent, lost after session). The advice file survives.

Every agent reads ADVICE.md at three moments:
1. **Before starting a task** — to absorb context from prior rounds
2. **After receiving advice** — to cross-reference with the persistent record
3. **Before completing a task** — to ensure nothing was missed

Every agent writes to ADVICE.md when:
1. **Sending advice** — the navigator dual-writes (SendMessage for delivery, file for persistence)
2. **Resolving advice** — the driver appends a resolution entry (fixed, acknowledged, incorporated, dismissed + why)

The resolution entries are as important as the advice itself. "Dismissed because the upstream validation already handles this case" is information the next driver needs. "Incorporated in checkpoint 3" points back to the LOG.md entry with the implementation details. The resolution closes the loop and leaves a trail.

### Single Source of Truth

A recurring failure mode in multi-agent systems is state desync. Two agents maintain separate views of who is doing what, and those views diverge. Agent A thinks it's driving; Agent B also thinks it's driving. Both edit the same file.

The solution is to have exactly one source of truth for each piece of coordination state, and to use the most authoritative source available.

**Who is driving?** The native TaskList. The driver is whoever owns the `in_progress` task. Not a LOCK.md file that might be stale. Not a field in CONTEXT.md that might not have been updated. The TaskList is the platform's coordination primitive — use it for coordination.

**What needs to be done?** The native TaskList with dependencies. Not a checklist in a markdown file. Task dependencies handle blocking automatically. When task 2 completes, task 3 unblocks. No agent needs to check a file to know.

**What happened?** LOG.md. Messages are ephemeral and capped. The log file is the permanent record, written by the agents doing the work.

**What was objected to?** ADVICE.md. The persistent record of typed advice and its resolution. Messages delivered the advice in real time; the file records it for history.

Every piece of state lives in exactly one place. The native platform handles coordination state (tasks, ownership, blocking). Files handle historical state (what happened, what was decided). Messages handle real-time state (advice, checkpoints, coordination).

### Ephemeral Conversation, Durable Memory

SendMessage and files serve different temporal purposes.

Messages are conversation. They're real-time, auto-delivered, and contextual. The navigator sends "OBJECTION: that depth check is wrong" and the driver gets it immediately. But messages are capped at 50 per agent and lost after the session ends.

Files are memory. LOG.md and ADVICE.md survive the session. A future session — or a human — can read them and reconstruct what the team did, what was debated, and how objections were resolved. The dual-write pattern (SendMessage for delivery + file append for persistence) costs extra work per entry but preserves the audit trail.

This maps to how real teams work. Conversations happen in real time and are forgotten. Decisions get written down. The meeting is the message; the meeting notes are the file.

### Constraining the Lead

Most agent orchestration systems give the lead maximum capability — all tools, all access, full authority. The lead reads files to understand context, writes files to set up state, and delegates only when it decides to.

This creates a gravitational pull toward centralization. The lead can always "help" by reading one more file, synthesizing one more result, making one more decision. Each small act of helping reduces the teammates' autonomy. Eventually the lead is doing most of the cognitive work and the teammates are executing narrow instructions — the batch query pattern again.

Coordinator mode inverts this. The lead has the narrowest tool set of any agent in the system. It can think, plan, create tasks, spawn agents, and send messages. It cannot read a file, run a command, or edit code.

This forces a different leadership style. The lead must break the problem into tasks that are self-contained enough for teammates to execute independently. It must write task descriptions that carry enough context. It must trust teammates to make decisions within their scope. When the lead can't peek at the code, it has to trust the team's reports.

This is harder than doing everything yourself. It's also the only way to get the collaboration benefits that XP pair programming promises.

### The `claude --bare` Escape Hatch

Teammates can optionally spawn focused micro-tasks via `claude --bare -p` — disposable single-shot agents with no hooks, no plugins, no memory. These are useful for tightly constrained work: "run this one test and report the output," "check if this import exists in that file."

In an earlier version of this architecture, `--bare` micro-tasks were the primary coordination mechanism. The coordinator would pause between micro-tasks to check shared files — artificial checkpoints for a system without real-time messaging.

With SendMessage, that role is gone. Messages arrive automatically. But `--bare` remains useful as a context management tool. A teammate working on a complex task might spawn a `--bare` sub-agent for a narrow verification rather than polluting its own context window with test output it doesn't need to remember.

## File Structure

```
popcorn-xp/
├── SKILL.md                  # Skill definition (triggers, workflow for the lead)
├── agents/                    # Teammate agent definitions
│   ├── scout.md              # Scope mapping, constraint discovery
│   ├── craftsman.md          # Implementation, readability, minimal changes
│   ├── expert.md             # Edge cases, invariants, correctness (has project memory)
│   ├── tester.md             # Test strategy, regression hunting, verification
│   ├── strategist.md         # Planning, sequencing, positioning, roadmap tradeoffs
│   ├── service-designer.md   # API design, service boundaries, contracts
│   ├── visual-designer.md    # UI/UX, accessibility, visual patterns
│   ├── qa.md                 # Acceptance testing, user flows, end-to-end verification
│   └── product-manager.md    # Requirements, scope, prioritization
├── references/
│   └── protocol.md           # Teammate instructions, prompt templates, advice format
├── hooks/
│   ├── hooks.json            # Advice lifecycle hooks (TaskCompleted, TeammateIdle)
│   └── scripts/
│       ├── check-advice-on-complete.sh  # TaskCompleted: blocks on OBJECTIONs, reminds on rest
│       └── enforce-no-idle.sh           # TeammateIdle: reminds of all open advice items
├── research/                  # Architecture research (not loaded at runtime)
│   ├── agent-teams.md
│   ├── agent-types.md
│   ├── coordinator.md
│   └── team-management.md
├── README.md
├── LICENSE
└── .gitignore
```

At runtime, `SKILL.md` is loaded by Claude Code via skill auto-discovery. The lead includes `references/protocol.md` in teammate prompts. The `hooks/hooks.json` registers the two advice lifecycle hooks (TaskCompleted, TeammateIdle) that enforce the advice lifecycle — both are no-ops when no `.popcorn-xp/ADVICE.md` exists.

## Limitations

- **Experimental** — Agent Teams is a research preview. The feature may change or be removed.
- **Claude-only** — This repository installs through `npx skills`, but the runtime workflow only works in Claude Code.
- **Token cost** — Each teammate has its own context window. 3 agents = ~3x token cost.
- **Context isolation** — Teammates don't share context windows. They communicate via messages, not shared memory. Important context must be sent explicitly.
- **Message cap** — 50 messages per teammate before oldest are dropped. Long sessions may lose early messages (LOG.md and ADVICE.md preserve the history).
- **Special env flags required** — Set `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` and `CLAUDE_CODE_COORDINATOR_MODE=1` before starting Claude Code.
- **Coordinator mode required** — The lead needs coordinator mode to enforce the "no direct file access" constraint. Without it, the lead tends to do everything itself.
- **Opus 4.6 required** — Agent Teams requires the Opus model.

## Credits

Built on Claude Code's Agent Teams and Coordinator Mode. Inspired by Extreme Programming's pair programming practices — short turns, frequent rotation, collective code ownership, and the courage to say "that's wrong."
