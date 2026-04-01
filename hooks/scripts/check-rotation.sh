#!/bin/bash
set -euo pipefail

# check-rotation.sh
# TaskCompleted hook: warns when all completed tasks have the same driver.
# At least one rotation per session is mandatory — this catches the lead
# before they let a single agent drive the entire session.
# No-op when no active popcorn-xp session or fewer than 2 completed tasks.

# Read hook input from stdin — TaskCompleted provides team_name
INPUT=$(cat)
TEAM_NAME=$(echo "$INPUT" | jq -r '.team_name // empty' 2>/dev/null)

# If no team_name in hook input, scan for the most recently modified tasks directory
if [ -z "$TEAM_NAME" ]; then
  TASKS_BASE="${HOME}/.claude/tasks"
  [ ! -d "$TASKS_BASE" ] && exit 0
  TASKS_DIR=$(ls -td "$TASKS_BASE"/*/ 2>/dev/null | head -1)
  [ -z "$TASKS_DIR" ] && exit 0
  # Remove trailing slash
  TASKS_DIR="${TASKS_DIR%/}"
else
  TASKS_DIR="${HOME}/.claude/tasks/${TEAM_NAME}"
fi

[ ! -d "$TASKS_DIR" ] && exit 0

# Collect owners of completed tasks
owners=()
for task_file in "$TASKS_DIR"/*.json; do
  [ ! -f "$task_file" ] && continue
  status=$(grep -o '"status":"[^"]*"' "$task_file" 2>/dev/null | head -1 | cut -d'"' -f4 || true)
  [ "$status" != "completed" ] && continue
  owner=$(grep -o '"owner":"[^"]*"' "$task_file" 2>/dev/null | head -1 | cut -d'"' -f4 || true)
  [ -z "$owner" ] && continue
  owners+=("$owner")
done

# Need at least 2 completed tasks to evaluate rotation
[ "${#owners[@]}" -lt 2 ] && exit 0

# Check if all owners are the same
unique_owners=$(printf '%s\n' "${owners[@]}" | sort -u | wc -l | tr -d ' ')

if [ "$unique_owners" -eq 1 ]; then
  completed=${#owners[@]}
  driver="${owners[0]}"

  # Count remaining pending/in_progress tasks
  remaining=0
  for task_file in "$TASKS_DIR"/*.json; do
    [ ! -f "$task_file" ] && continue
    status=$(grep -o '"status":"[^"]*"' "$task_file" 2>/dev/null | head -1 | cut -d'"' -f4 || true)
    [ "$status" = "pending" ] || [ "$status" = "in_progress" ] && remaining=$((remaining + 1))
  done

  if [ "$remaining" -gt 0 ]; then
    echo "{\"systemMessage\":\"Popcorn XP rotation warning: ${driver} has driven all ${completed} completed task(s) with ${remaining} task(s) remaining. At least one rotation is mandatory per session — assign the next task to a different driver. The navigator carries context from watching and should drive next.\"}"
  else
    echo "{\"systemMessage\":\"Popcorn XP rotation warning: ${driver} drove all ${completed} task(s) in this session with no rotation. Note this in the retro — a session with no rotation is a solo session with an expensive spectator.\"}"
  fi
fi

exit 0
