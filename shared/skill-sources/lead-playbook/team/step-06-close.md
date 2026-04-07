### 6. Verify and Close

When all tasks are complete, follow this sequence exactly. Do not skip steps or reorder — the retro conversation happens **before** shutdown, shutdown happens **before** TeamDelete, and the retro file is written **after** shutdown.

1. Ask a teammate (typically the **tester** if on the bench, otherwise the **navigator** or **driver** of the last pair) to run final verification.
2. Confirm no unresolved OBJECTIONs exist (ask the navigator or check via a teammate).
3. **Check ADVICE.md for open SMELLs, STEERs, and FYIs.** For each: (a) resolve it now if trivial, (b) create a follow-up task if it warrants future work, or (c) note it in the retro. Do not let the session end with unacknowledged open items.
4. **Retrospective (mandatory — mechanical).** Run the session retro-request subcommand, then notify each teammate:

   ```bash
   .popcorn-xp/{team-name}/session retro-request
   ```

   ```
   SendMessage(to: "craftsman", summary: "retro time", message: "Retro time. Submit your process observations: .popcorn-xp/{team-name}/session retro craftsman 'What worked? What didn't? What would you change about the process?'")
   ```

   The `enforce-no-idle.sh` hook will nudge any idle teammate automatically. After retro-request, wait for all `.retro-*.md` files before writing RETRO.md. The FileChanged hook will notify you as each one arrives.

   If an agent sends their retro text via SendMessage instead of running the session script themselves, record it on their behalf: `.popcorn-xp/{team-name}/session retro {agent} '{text}'`. This creates the `.retro-{agent}.md` file so the shutdown lifecycle proceeds normally.
5. **Shut down all teammates — explicitly.** Run the shutdown subcommand, then send a shutdown_request to each teammate:

   **Important:** Send a retro request to each agent BEFORE issuing shutdown. The retro-pending phase in `enforce-no-idle.sh` takes priority over shutdown, ensuring agents can write their retro even after `.shutdown` is set. But sending the retro request first gives agents a turn to write while still fully active.

   ```bash
   .popcorn-xp/{team-name}/session shutdown
   ```

   Then send an explicit shutdown_request to each teammate (the hook alone is not sufficient — `{"continue": false}` does not reliably stop agents):

   ```
   SendMessage(to: "craftsman", message: {"type": "shutdown_request"})
   SendMessage(to: "expert", message: {"type": "shutdown_request"})
   ```

   Agents will approve the shutdown_request, which terminates their session. The `enforce-no-idle.sh` hook will also remind any idle agent to approve a pending shutdown_request. Proceed to TeamDelete once all teammates have shut down.
6. **Write the retro file.** After teammates shut down, write `.popcorn-xp/{team-name}/RETRO.md` with your assessment of the session. This is YOUR perspective as the lead — what you observed about how the team worked, not just what they built. Use the format below.
7. **Confirm `RETRO.md` exists before the final user summary.** Do not present the technical summary until `.popcorn-xp/{team-name}/RETRO.md` exists and contains the session entry you just wrote.
8. Present a technical summary to the user: what was done, what each role found, any remaining risk. Include a brief retro summary (2-3 bullets on what worked, what didn't, what to change next time).
9. After teammates have shut down (or after 3 failed shutdown attempts):

   ```
   TeamDelete
   ```
