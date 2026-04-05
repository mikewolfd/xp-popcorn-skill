---
name: Session script file is fragile — haiku agents overwrite it
description: The per-team session wrapper at .popcorn-xp/{team}/session was overwritten 3+ times in a single session by haiku agents interpreting it as a writable status file.
type: project
---

The per-team session script at `.popcorn-xp/{team}/session` was overwritten 3+ times in the 2026-04-04 session. Haiku agents interpreted "log to session" as "write my status to the session file." The thin wrapper approach (exec to bin/session) makes this worse — a 3-line file looks trivially editable.

**Why:** Haiku agents see any file in the team directory as a place to write status. The session wrapper lives alongside LOG.md and ADVICE.md, so it looks like a peer file to write to.

**How to apply:** Either (a) make the wrapper read-only at creation time, (b) have agents call bin/session via the plugin path directly instead of through a per-team wrapper, or (c) replace the script entirely with direct printf appends in spawn prompts. Option (a) is simplest. The underlying bin/session is safe — it's in the plugin dir, not the team dir.
