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

