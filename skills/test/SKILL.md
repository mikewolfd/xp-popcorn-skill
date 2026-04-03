---
name: test
description: Run the popcorn-xp test suite. First runs unit tests for all hook scripts, then launches a live popcorn-xp session against the context-store-exercise project to validate context store hooks end-to-end, and verifies the results.
---

# Test

This skill runs the popcorn-xp test suite in two phases.

## Phase 1: Unit Tests

Run the hook unit tests first. If these fail, stop — don't proceed to Phase 2 with broken hooks.

```bash
./tests/test-hooks.sh
```

Test naming conventions:

- **no-op**: Hook exits 0 with no output when no active session
- **H1-H6**: Core hook behavior (exit codes, output channels, advice resolution)
- **R3-R4**: Session script subcommands (edit counter, shutdown lifecycle)
- **CS1-CS13**: Context store (read tracking, dirty flags, soft locks, path skipping)
- **CL1-CL8**: Context store event log (timestamps, event types, entry counts)

If any tests fail, fix the hook script (not the test file) and re-run.

## Phase 2: Integration Test

Once unit tests pass, launch a live popcorn-xp session against the exercise project to validate the context store hooks fire correctly in a real multi-agent session.

**Invoke the popcorn-xp skill** with this task:

> Popcorn this task: Implement the discount system described in `context-store-exercise/CLAUDE.md`. Add a `DiscountRule` dataclass in `context-store-exercise/src/models.py`, a `calculate_discount` function in `context-store-exercise/src/service.py`, validation in `context-store-exercise/src/validators.py`, and tests. Both agents must touch `models.py` — the driver adds the dataclass, the navigator fixes type hints or adds docstrings to existing models while reviewing.

Use **2 agents** (craftsman + expert is a good default). The session should produce cross-agent file reads, dirty tracking, and ideally a soft lock on `models.py`.

## Phase 3: Verification

After the session completes and TeamDelete is done, run the verification suite from the project root:

```bash
bash context-store-exercise/bin/verify-exercise.sh
bash context-store-exercise/bin/inspect-store.sh
```

`verify-exercise.sh` checks:
- At least 3 files tracked in the context store
- At least 2 different agents recorded as readers
- No "unknown" agent names — all should be `popcorn-xp:*`
- At least 1 file marked dirty
- All dirty files have `edited_by` set
- Non-empty previews stored
- Event log exists with READ, EDIT, and cache hit entries
- Reports soft lock count (informational)

`inspect-store.sh` pretty-prints the store contents and the event log tail for manual review.

**Pass criteria**: All `verify-exercise.sh` checks pass, and the event log shows at least one cache hit (proving the PreToolUse(Read) hook informed an agent about a prior read).

If verification fails, review the event log at `.popcorn-xp/context-store.log` to diagnose which hooks didn't fire and why.
