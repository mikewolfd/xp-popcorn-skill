Assign the first task pair — both the drive task and navigate task — simultaneously using the **task bus** (not `TaskUpdate`):

- Run **`session task-init 1`** (and matching ids for other pairs), then establish the driver atomically with **`session task-start 1 {driver-agent} "next action" -- <owned files...>`**. This is the hard pre-edit gate: the driver should not be resumed for editing until the claim, state, and write set all exist.
- Then run **`session task-claim 1 {navigator-agent} navigator`** and **`session task-claim 1 {advisor-agent} advisor`** (use real agent short names from **meta.json**), plus **`session state`** / **`session writeset`** for the navigator as needed. Use **`session chat`** for tactical back-and-forth; wake stalled subagents with **resume** or an explicit prompt — not `SendMessage` between teammates.
- The navigator begins reviewing immediately — they do not wait for the driver to start.
- After kickoff, run **`session health --strict`** once. Treat any missing driver state or empty write set as a session-mechanics failure, not as something to clean up later.
