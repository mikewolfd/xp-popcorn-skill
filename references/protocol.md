# Popcorn XP Protocol

Use this file as the reusable coordination layer for any skills.sh-compatible agent that supports delegation or subagents.

## Session Files

Create a `.popcorn-xp/` directory in the working repo and maintain these files:

- `CONTEXT.md`: task statement, roster, checklist, and active constraints
- `LOCK.md`: source of truth for the active round and driver
- `LOG.md`: detailed execution history plus in-turn checkpoints
- `ADVICE.md`: the single place where non-driver agents leave steering input

If the host agent does not let subagents write to shared files directly, the orchestrating agent must mirror their outputs into these files immediately. In that case, subagents should return append-ready `LOG.md` or `ADVICE.md` blocks instead of being told to write files themselves. The file layout still matters because it keeps the session state inspectable and stable.

Treat `LOG.md` and `ADVICE.md` as append-only. Do not rewrite prior entries to "clean them up." Preserve the session history.

## Core Rules

1. The main agent owns integration, the main-thread workspace, and final verification.
2. Exactly one agent is the driver in a given round. Everyone else advises, reviews, or scouts.
3. Each round should also have one primary navigator who stays strategic while the driver stays tactical.
4. Subagents work in short rounds with one concrete output each.
5. `LOCK.md` is the source of truth for who is currently driving.
6. Keep WIP low. Do not open a second active implementation thread while the current round is unresolved.
7. Prefer frequent driver rotation across rounds to spread knowledge and maintain collective ownership.
8. Do not give two agents overlapping write ownership.
9. Put all steering guidance in `ADVICE.md`. Do not hide advice inside `LOG.md` or chat-only summaries.
10. Relay state explicitly between rounds using the platform's native follow-up mechanism, or launch a fresh round with the latest summary.
11. Keep the collaboration small. Three agents is usually enough.
12. Append to `LOG.md` and `ADVICE.md`; do not rewrite history.
13. Mirror the current driver in `CONTEXT.md` and `ADVICE.md`, but treat `LOCK.md` as authoritative.
14. Give every advice item a stable ID and resolve it by ID.

## Driver And Navigator Model

Use a real pair-programming mental model:

- The driver is the only agent making code changes in that round.
- The navigator watches, steers, challenges assumptions, and points out risks.
- The navigator should know enough about the active work to give useful advice before the handoff, not only after it.
- The driver should stay concrete and tactical.
- The navigator should stay one level more strategic: intent, simplification, edge cases, and next steps.
- Additional agents may advise, but they should not crowd out the primary navigator or become parallel drivers.

To support that, the driver must keep `LOG.md` current during the round, not just at the end. Add a checkpoint before any major edit, before any test run, and whenever the driver changes plan. For tiny rounds, at minimum add one checkpoint before handoff.

The driver must also re-read new entries in `ADVICE.md` during the round:

- after each new checkpoint
- before any major edit
- before any test run
- before handoff

Before a round starts, update `LOCK.md` to name the current driver. When the round ends, update it to the next driver or `done`.

After every `LOCK.md` change, immediately sync the mirrored current-driver sections in `CONTEXT.md` and `ADVICE.md`.

Rotate the driver at natural boundaries: after a small goal lands, when a different lens is needed, or when focus is fading. Do not rotate mid-edit unless there is a good reason.

## Host Capability Rule

Choose one execution mode per host:

- Shared-write mode: subagents can append directly to the session files.
- Mirrored-write mode: subagents return append-ready blocks in their replies, and the orchestrator writes those blocks into the session files.

Do not mix the instruction set. On mirrored-write hosts, never tell subagents to write files directly.

## File Templates

### `CONTEXT.md`

```markdown
# Task: {short title}

{task summary}

## Roles
- `scout`: {one-line purpose}
- `craftsman`: {one-line purpose}
- `expert`: {one-line purpose}
- `tester`: {one-line purpose}

## Current Driver
- Round {N}: `{role}` — {goal}
- Navigator: `{role}`
- Status: {driving | done}

## Checklist
- [ ] {item}
- [ ] {item}
- [ ] Final verification
```

### `LOCK.md`

This file is the source of truth for who is currently driving.

```markdown
# Popcorn XP Lock

- Round: {N}
- Driver: @{role}
- Navigator: @{role}
- Status: driving
- Goal: {one concrete chunk}
```

Rules:

- Only one active driver at a time.
- Update this file before code changes begin.
- Change `Driver` and `Round` on handoff.
- Set `Status: done` when the checklist is complete and verified.
- Mirror the current driver in `CONTEXT.md` for readability, but treat `LOCK.md` as authoritative.
- Mirror the same current-driver state in `ADVICE.md`.

### `ADVICE.md`

This file is for steering only.

```markdown
# Popcorn XP Advice

## Current Driver
- Round {N}: `{role}`
- Navigator: `{role}`
- Status: {driving | done}

## Advice Queue
### Advice A-{NNN} — @{target-role} from @{author-role}
- Round: {N}
- Context: {what you observed}
- Suggestion: {specific steer}
- Why it matters: {risk or payoff}

### Advice A-{NNN} — @{target-role} from @{author-role}
- Round: {N}
- Context: {what you observed}
- Suggestion: {specific steer}
- Why it matters: {risk or payoff}

## Resolved
### Advice A-{NNN}
- Resolved by: @{role}
- Outcome: {used / rejected / no longer relevant}
- Notes: {short reason}
```

Rules:

- Append new advice instead of rewriting history.
- Be specific. Point to a file, test, assumption, or edge case.
- Keep advice actionable enough that the driver can immediately use or reject it.
- When advice is no longer active, append a matching item under `## Resolved` instead of deleting the original entry.
- Resolve advice by ID, not by vague description.

### `LOG.md`

This file is for execution history, not steering.

```markdown
# Popcorn XP Log

## Round {N} — Driver @{role}
### Pairing Setup
- Navigator: @{role}
- Other active advisors: @{role}, @{role}

### Goal
- {one concrete chunk for this round}

### Starting Point
- Files inspected: `{path}`, `{path}`
- Relevant state already known: {brief summary}
- Advice reviewed: {which items from ADVICE.md mattered}

### Checkpoints
#### Checkpoint {K}
- Working in: `{path}`
- Change in progress: {what the driver is attempting}
- Observation: {what was learned mid-round}
- Possible risk: {what advisors should react to right now}

#### Checkpoint {K}
- Working in: `{path}`
- Change in progress: {what the driver is attempting next}
- Observation: {what changed since the prior checkpoint}
- Possible risk: {what advisors should react to right now}

### Completed Work
- Updated `{path}` to {specific change}
- Added or adjusted `{test-path}` to cover {behavior}
- Rejected {alternative} because {reason}

### Verification
- Ran: `{command}`
- Result: {pass/fail and the important output}

### Handoff State
- Current code state: {what is true now}
- Open question: {if any}
- Recommended next role: @{role}
- Recommended next move: {one concrete next chunk}

## Final Session Summary
- Outcome: {what shipped or what was decided}
- Final verification: {what was run and whether it passed}
- Remaining risk: {if any}
```

## Detailed Log Example

Use this level of detail, not vague bullets like "updated code" or "ran tests."

```markdown
## Round 3 — Driver @craftsman
### Pairing Setup
- Navigator: @expert
- Other active advisors: @tester

### Goal
- Tighten nested repeat parsing without changing the public API

### Starting Point
- Files inspected: `src/parser.ts`, `src/parser.test.ts`
- Relevant state already known: nested repeats currently recurse, but invalid closing tokens fall through to a generic parse error
- Advice reviewed: expert suggested checking unmatched `endRepeat`; tester suggested preserving the existing happy-path snapshots

### Checkpoints
#### Checkpoint 1
- Working in: `src/parser.ts`
- Change in progress: splitting `parseRepeatBlock` into token validation and body parsing
- Observation: the parser already tracks depth, so unmatched `endRepeat` can be surfaced earlier without new state
- Possible risk: changing the thrown error message may break snapshot assertions

#### Checkpoint 2
- Working in: `src/parser.test.ts`
- Change in progress: adding regression coverage before touching snapshots elsewhere
- Observation: the existing happy-path tests still pass with the parser refactor in place
- Possible risk: broader snapshot suites may still depend on the old generic error message

### Completed Work
- Updated `src/parser.ts` so unmatched `endRepeat` throws `Unexpected endRepeat at depth 0`
- Kept the recursive parse shape and avoided changing the outer `parse()` signature
- Added regression tests in `src/parser.test.ts` for unmatched `endRepeat` and nested valid repeats

### Verification
- Ran: `pnpm test src/parser.test.ts`
- Result: pass; 12 tests passed, including 2 new regression tests

### Handoff State
- Current code state: parser behavior is unchanged on valid input and now fails earlier on unmatched closing tokens
- Open question: should the new error message be normalized to match other parser errors
- Recommended next role: @tester
- Recommended next move: decide whether the new message should be snapshot-stable across all parse errors

## Final Session Summary
- Outcome: parser now rejects unmatched `endRepeat` earlier without changing valid nested repeat behavior
- Final verification: `pnpm test src/parser.test.ts` passed with 12/12 tests green
- Remaining risk: broader parser snapshot suites may still want a normalized error-message format
```

## Role Blurbs

Use these as the role paragraph in launch prompts.

### Scout

You are `scout`. Your lens is: "Are we solving the right problem?" Map the repo, identify the minimal set of touched files, surface unknowns early, and point out where the task can go wrong. Do not drift into broad architecture commentary unless it changes the implementation path.

### Craftsman

You are `craftsman`. Your lens is: "Is this clean and readable?" Focus on implementation shape, naming, module boundaries, and the smallest maintainable change that solves the problem. Prefer concrete patch guidance over generic style advice.

### Expert

You are `expert`. Your lens is: "Does this actually work in edge cases?" Check invariants, hidden coupling, state transitions, parsing assumptions, and behavior that tends to break under real input. Be specific about failure modes.

### Tester

You are `tester`. Your lens is: "How will we prove this?" Identify the smallest convincing test set, likely regressions, missing assertions, and any manual verification still required. Prefer exact test names or scenarios when possible.

## Round 1 Prompt Template

Use this template when launching a fresh agent:

```text
You are participating in a Popcorn XP coding session.

Role: {role}
Lens: {one-line role blurb}
Round role: {driver | navigator | advisor}

Task:
{task summary}

Current context:
{repo facts, files already inspected, constraints, assumptions}

Your ownership for this round:
{bounded scope}

Return:
1. What you checked
2. What you learned
3. What should happen next

Important:
- You are not alone in the codebase. Do not revert or overwrite work you did not make.
- Keep this round small and focused.
- If you propose code changes, keep them inside your owned scope.
- Respect `LOCK.md`. Only the active driver should be editing.
- If you are the navigator, stay strategic and steer the driver instead of grabbing the keyboard.
- If you are an advisor, keep input concise and avoid creating a second navigation channel.
- If the host supports shared file writes, append steering input to `ADVICE.md` and execution detail to `LOG.md`.
- If the host does not support shared file writes, return append-ready `ADVICE.md` or `LOG.md` entries so the orchestrator can mirror them.
```

## Follow-Up Round Template

Use this template when following up with an existing agent or launching the next short round:

```text
Popcorn follow-up for {role}.

Latest state:
{short synthesis of what changed or what another agent found}

Your next small chunk:
{one concrete question, review pass, or bounded patch}

Return only:
1. Findings
2. Recommended next move
3. Any exact test or file follow-up
```

## Suggested First Round Split

For most coding tasks:

- `scout`: map touched files, entry points, and constraints
- `expert`: check correctness and edge-case risks
- `tester`: propose the smallest convincing test plan

Add `craftsman` when the implementation is non-trivial or you want a second opinion on code shape.

Suggested pairing shape:

- driver: whichever role is best suited to the current code change
- navigator: `expert` or `scout` when correctness or direction is the bigger risk
- advisor: `tester` when verification pressure matters

## Integration Guidance

- Keep final edits and test runs in the main thread unless a delegated patch is clearly isolated.
- If a worker returns a patch idea, review it against the main-thread understanding before integrating.
- Stop the multi-agent loop once additional rounds stop changing the plan.
- Before changing drivers, update `LOCK.md`.
- After changing drivers, sync the mirrored current-driver sections in `CONTEXT.md` and `ADVICE.md`.
- Before choosing the next driver, read the latest `LOG.md` and unresolved items in `ADVICE.md`.
- During an active round, the driver must keep checking for new `ADVICE.md` entries at the defined checkpoints.
- Prefer a new driver when the next round benefits from a different lens or when you want to spread knowledge of the touched code.
- On session close, set `LOCK.md` to `done`, append a final session summary to `LOG.md`, and append resolution markers for any no-longer-active advice.
