Assign the first task pair — both the drive task and navigate task — simultaneously. SendMessage both agents with their task metadata:

- Driver: `TaskUpdate(T1-drive, assigned to craftsman)` + SendMessage with:
  `.popcorn-xp/{team-name}/session state {agent} driver driving {task-id} - 'Implement the assigned task and checkpoint after meaningful edits.'`
  `.popcorn-xp/{team-name}/session writeset {agent} {task-id} <owned files...>`
- Navigator: `TaskUpdate(T1-nav, assigned to expert)` + SendMessage with:
  `.popcorn-xp/{team-name}/session state {agent} navigator navigating {task-id} {driver} 'Read the spec/code and publish a READY artifact before edits start.'`

Both agents receive their assignments at the same time. The navigator begins reviewing immediately — they do not wait for the driver to start.
