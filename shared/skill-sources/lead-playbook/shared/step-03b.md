
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

