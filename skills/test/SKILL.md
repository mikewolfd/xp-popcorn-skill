---
name: test
description: Run the popcorn-xp test suite. Runs unit tests for all hook scripts and validates hook behavior against canonical exit code semantics.
---

# Test

This skill runs the popcorn-xp test suite.

## Unit Tests

Run the hook unit tests:

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
