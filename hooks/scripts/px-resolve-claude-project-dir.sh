#!/bin/bash
# popcorn-xp — resolve repository / project root from a starting directory.
# Used by Codex hooks (stdin .cwd may be a subdirectory) and bin/session when
# CLAUDE_PROJECT_DIR is unset. Prefer git(1) toplevel; fall back to the start dir.

# px_resolve_project_dir_from START_DIR
# Prints one line: absolute path. No trailing newline issues if used in $( ).
px_resolve_project_dir_from() {
  local start="${1:-.}"
  [ -z "$start" ] && start="."
  [ ! -d "$start" ] && start="."
  local root
  root=$(git -C "$start" rev-parse --show-toplevel 2>/dev/null) || root=""
  if [ -n "$root" ]; then
    printf '%s' "$root"
    return 0
  fi
  # No git metadata — Codex cwd (or shell cwd) is the best we can do.
  (cd "$start" && pwd)
}
