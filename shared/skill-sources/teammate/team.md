## Team mode (Claude Agent Teams only)

The sections above define shared rules, advice lifecycle, and session file shapes. **This section is only the Agent Teams transport** — tactical peer messaging, completion order, and tool-specific locks.

When `.popcorn-xp/{team}/.runtime-mode` contains **`team`**:

- **Tactical peer channel:** Use **`SendMessage`** for coordination — this is your primary channel for discussion, negotiation, and declaring intent.
- **Declare intent:** Before going idle or switching focus, state what you plan to do next via **`SendMessage`** and mirror it into session state so your partner can plan and catch misalignment early.
- **Navigator completes after driver:** When you finish your drive task, run tests, then call `TaskUpdate(status=completed)` after `session log` once tests pass — do not wait for the navigator. The navigator then does a final verification pass and completes their navigate task. If verification reveals issues, send advice (OBJECTIONs if warranted) before completing.

**Between checkpoints (navigators and advisors):**

- **Edit signal:** Check `.popcorn-xp/{team-name}/context-store.log` for recent edits by the driver. Read the changed files (oldest to newest) and do a quick informal review pass.
