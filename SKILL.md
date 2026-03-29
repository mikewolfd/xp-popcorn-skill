---
name: popcorn-xp
description: Use when the user explicitly asks for a multi-agent coding session such as "pair program", "xp session", "popcorn", "team of agents", or "work together on this with subagents". Runs a short-turn XP-style collaboration where the main agent orchestrates 3-4 subagents with distinct lenses, relays findings between rounds, and integrates the final code and verification.
---

# Popcorn XP

Run a small team around one coding task. Preserve the XP idea of frequent handoffs and different perspectives, but adapt it to the current agent's native delegation model:

- The main agent owns integration, testing, and the user-facing thread.
- Subagents explore, review, design tests, and optionally attempt bounded patches.
- Collaboration happens through short rounds, relayed summaries, and shared session notes.

## XP Shape

Model each round like XP pairing:

- one active driver edits
- one active navigator steers in real time
- any additional agents advise briefly without becoming extra drivers
- goals stay small enough that rotation is normal
- the team keeps WIP low and collectively owns the code

## Use Only On Explicit Multi-Agent Requests

Trigger this skill when the user explicitly asks for a team-style workflow, for example:

- "pair program on this"
- "run an XP session"
- "use subagents"
- "let a team of agents work this"
- "popcorn this task"

Do not use this skill for ordinary single-agent coding.

## Role Roster

Prefer 3 agents by default. Use 4 only when the task has enough surface area to justify it.

- `scout`: repo mapping, requirements, affected files, unknowns
- `craftsman`: implementation shape, API boundaries, refactors, readability
- `expert`: invariants, edge cases, correctness risks
- `tester`: test plan, regression coverage, validation gaps

The role is the lens, not the limit. Any agent may inspect code, review, write tests, or suggest implementation details.

## Workflow

1. Inspect the repo yourself first.
   - Read the relevant files locally before delegating.
   - Decide the immediate local next step before spawning agents.
   - Build a checklist with 3-6 concrete items.

2. Create session files.
   - Create `.popcorn-xp/CONTEXT.md`, `.popcorn-xp/LOCK.md`, `.popcorn-xp/LOG.md`, and `.popcorn-xp/ADVICE.md`.
   - `CONTEXT.md` holds the task, roster, and checklist.
   - `LOCK.md` is the source of truth for who is currently driving.
   - `LOG.md` holds detailed execution history and progress checkpoints.
   - `ADVICE.md` is the single place for steering input from non-driver agents.
   - Treat `LOG.md` and `ADVICE.md` as append-only history.
   - Mirror the current driver in `CONTEXT.md` and `ADVICE.md`, but treat `LOCK.md` as authoritative.
   - If the host does not let subagents write shared files directly, have them return append-ready log or advice entries and mirror those entries into the files from the main thread.

3. Launch round 1 in parallel.
   - Use the platform's native subagent or delegation mechanism.
   - Start up to 4 subagents in one batch.
   - Give each role a non-overlapping task and a concrete deliverable.
   - Keep the first round focused on orientation, correctness risks, and test strategy.

4. Synthesize locally.
   - Continue reading code while agents run.
   - Merge their outputs into one concrete plan.
   - Wait only on the result that blocks the next critical-path step.

5. Run popcorn rounds.
   - Pick exactly one driver for each round.
   - Pick one primary navigator for that round.
   - Any additional agents act as lightweight reviewers or advisors, not extra drivers.
   - Reuse the same agents if the platform supports follow-up messaging; otherwise launch a fresh short round with the latest state.
   - Each round should be one small chunk with one immediate goal: inspect one risk, validate one assumption, draft one bounded change, or design one test slice.
   - Before the driver starts, update `LOCK.md`, sync the mirrored current-driver sections in `CONTEXT.md` and `ADVICE.md`, then read the latest `LOG.md` and `ADVICE.md`.
   - During the round, record enough detail in `LOG.md` that other agents can steer while the driver is working.
   - During the round, re-read new entries in `ADVICE.md` after each checkpoint and before any major edit, test run, or handoff.
   - Add a new checkpoint entry before any test run, before any major edit, and whenever the driver changes plan.
   - Put all advice in `ADVICE.md`, not in scattered replies or mixed into the log, and give each advice entry a stable ID.
   - Rotate the driver regularly across rounds when a different perspective is useful or when you want to spread knowledge.
   - Keep WIP low: finish or hand off the current goal cleanly before opening another implementation thread.
   - When the round ends, update `LOCK.md` to the next driver or mark the session done, then sync `CONTEXT.md` and `ADVICE.md`.
   - Relay new state yourself. Do not assume subagents share live conversational state.

6. Integrate in the main thread.
   - Apply the final code edits in the main workspace unless a delegated worker owns a clearly disjoint patch you can review and integrate safely.
   - Never assign overlapping write ownership.
   - Run the relevant tests yourself before finalizing.

7. Close the loop.
   - Update `LOCK.md` to `done`.
   - Sync the mirrored current-driver sections in `CONTEXT.md` and `ADVICE.md`.
   - Add a final session summary to `LOG.md`.
   - Summarize what each role found.
   - Call out any unresolved risk or test gap.
   - Mark advice items as resolved or still-open in `ADVICE.md` by advice ID.
   - Close agents that are no longer needed.

## Good Round Sizes

- Identify touched modules and likely test files
- Check one invariant or edge-case family
- Draft one bounded patch in an owned file set
- Review one diff for regressions
- Propose exact test cases for one behavior
- Add checkpoint entries to `LOG.md` so advisors can react before handoff
- End the round with a clear next move so another driver can pick it up cleanly

## Bad Round Sizes

- "implement the whole feature"
- "review the entire repo"
- overlapping edits to the same files
- asking every agent the same question
- letting multiple agents code against the same live goal
- carrying multiple active implementation threads at once

## Prompt Pattern

Every subagent prompt should include:

- the task in one short paragraph
- the role lens
- whether the role is driver, navigator, or advisor
- explicit ownership
- the exact output you want next
- which round's driver is currently editing
- a reminder that it is not alone in the codebase and must not revert others' work

See `references/protocol.md` for reusable role blurbs, launch prompts, and follow-up prompt structure.

## Quality Bar

- Different roles must contribute materially different information.
- `ADVICE.md` is the only steering file. Do not split advice across multiple places.
- `LOCK.md` is the source of truth for the active driver.
- `LOG.md` and `ADVICE.md` are append-only session history.
- Mirrored current-driver sections in `CONTEXT.md` and `ADVICE.md` must stay synchronized with `LOCK.md`.
- Advice entries must have stable IDs so resolution is traceable.
- Drivers must check for new advice during the round, not only at the start or handoff.
- Each round should feel like a real XP pairing slice: one driver, one navigator, one small goal.
- Rotate drivers often enough to spread knowledge and avoid long solo runs.
- Keep WIP low and preserve collective code ownership.
- `LOG.md` must be detailed enough that the next agent can reconstruct what happened without guessing.
- Keep rounds short enough that you can redirect based on what you learn.
- The main thread remains responsible for correctness, integration, and final verification.
- If the task becomes straightforward after orientation, stop spawning more rounds and finish locally.

## Reference

Read `references/protocol.md` when you need prompt templates or role instructions.
