Assign the first task pair — both the drive task and navigate task — simultaneously using the **task bus** (not `TaskUpdate`):

- Run **`session task-init 1`** (and matching ids for other pairs), then **`session task 1`**, then **`session task-claim 1 {driver-agent} driver`**, **`session task-claim 1 {navigator-agent} navigator`**, **`session task-claim 1 {advisor-agent} advisor`** (use real agent short names from **meta.json**).
- **`session state`** / **`session writeset`** for the driver and navigator as in the protocol; use **`session chat`** for tactical back-and-forth; wake stalled subagents with **resume** or an explicit prompt — not `SendMessage` between teammates.
- The navigator begins reviewing immediately — they do not wait for the driver to start.
