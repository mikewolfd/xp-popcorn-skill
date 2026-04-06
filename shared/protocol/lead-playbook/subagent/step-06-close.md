### 6. Verify and Close

**Subagent plugin:** There is no **`TeamDelete`** gate — closeout is **`session close-check`** then **`session close`** (see **Subagent mode essentials** above). Do not skip retro before shutdown markers; the retro file is still written **after** teammates have submitted **`.retro-*.md`** (or handoffs).

1. Ask a teammate (typically the **tester** if on the bench, otherwise the **navigator** or **driver** of the last pair) to run final verification.
2. Confirm no unresolved OBJECTIONs exist (check **ADVICE.md** or ask via task chat).
3. **Check ADVICE.md for open SMELLs, STEERs, and FYIs.** For each: (a) resolve it now if trivial, (b) create a follow-up task if it warrants future work, or (c) note it in the retro. Do not let the session end with unacknowledged open items.
4. **Retrospective (mandatory — mechanical).** Run **`session retro-request`**, then nudge each subagent (resume / prompt) to run **`session retro {agent} '...'`** or hand in text you record with the same command.

   ```bash
   .popcorn-xp/{team-name}/session retro-request
   ```

   The `enforce-no-idle.sh` hook will nudge idle workers. Wait for all **`.retro-*.md`** files (or valid handoffs) before appending **RETRO.md**.
5. **Shut down workers.** Run **`session shutdown`**, then explicitly stop or retire each background subagent (product-specific stop / shutdown_request if you also used native team metadata). The retro-pending phase in **`enforce-no-idle.sh`** still takes priority over shutdown.
6. **Release the bus.** **`session task-release`** / **`task-complete`** / **`task-abandon`** as needed so no stale claims remain.
7. **`session close-check`** → append **RETRO.md** (≥5 real lines in the accumulated file) → **`session close`** (re-runs **`close-check`**, enforces **RETRO.md**; **`close --force`** skips gates). Successful **`close`** writes **`.closed.json`**, clears **`.popcorn-xp/.active-team`** when it still names this team, and truncates **`context-store.log`**.
8. Present a technical summary to the user: what was done, what each role found, any remaining risk. Include a brief retro summary (2-3 bullets on what worked, what didn't, what to change next time).

