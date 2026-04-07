## 1. Session setup

**Choose the teammate model.** Ask the user which model to use for teammates:

> What model should I use for the teammates? Options:
>
> - **gpt-5.4-mini xhigh** — fast and cheap, good default for most tasks *(default)*
> - **gpt-5.4 low** — full model, minimal reasoning
> - **gpt-5.4 medium** — full model, moderate reasoning
> - **gpt-5.4 high** — full model, maximum reasoning
>
> (Default: gpt-5.4-mini xhigh)

Store their choice as `{model}` and `{reasoning_effort}` and pass both to every subagent spawn call. If the user doesn't have a preference, default to `model="gpt-5.4-mini"` with `reasoning_effort="xhigh"`.

**Set up the session:**

1. Pick a short team name (e.g. `fix-auth`).
2. Create **`.popcorn-xp/{team}/`**, **`LOG.md`**, **`ADVICE.md`**, and a **`session`** wrapper that **`exec`**s your vendored **`shared/runtime/bin/session`**.
3. **`echo {team} > .popcorn-xp/.active-team`**
4. **`printf 'subagent\n' > .popcorn-xp/{team}/.runtime-mode`** (or omit **`.runtime-mode`** if **`shared/runtime/bin/session`** defaults to subagent).
5. Spawn **three** teammates (driver, navigator, advisor) with **`skills/...`** wired via **`[[skills.config]]`** in **`agents/*.toml`**, using the chosen `{model}` and `{reasoning_effort}`.

## 2. Tasks and pairing

- Each logical slice is a **pair**: **drive** + **navigate** task (navigator verifies after driver completes).
- **`session task-init {n}`** before work on task **n**.
- Use **`session task-start {n} {driver} "next action" -- <owned files...>`** to kick off the driver atomically. It records the task header if needed, claims the drive seat, writes driver state, and records the write set before edits begin.
- **`session task {n}`** remains available for a standalone **LOG.md** placeholder; real driver/navigator lines sync from **`task-claim`** / **`task-release`**.
- Claims: **`session task-claim`**, **`task-release`**, **`task-complete`**, **`task-abandon`** as in the **`popcorn-xp-protocol`** skill.
- Typed advice only in **`ADVICE.md`** (**`session advice`** / **`session resolve`**). **OBJECTION** blocks completion until resolved.

## 3. Chat and cursors (subagent)

- Tactical: **`session chat`** / **`session chat-read`** on **`tasks/T{n}/back-forth.md`**.
- Navigators in **`waiting_on_driver`**: keep **`cursor-ack`** current.
- Advisors: **`session review`** to advance review cursors when required.

## 4. Health and closeout

- Run **`session health`** (or **`--strict`**) before risky handoffs. In strict mode, missing driver state or an empty driver write set is a failure.
- For UI work, capture browser evidence at the first meaningful visual checkpoint, not only at closeout. End-of-session Playwright capture is a confirmation step, not the primary verification path.
- **`session retro-request`** → per-agent **`.retro-*.md`** or **`handoff-*.md`** as required.
- **`session close-check`** → append **`RETRO.md`** (≥5 real lines) → confirm **`RETRO.md`** exists before the final user summary → **`session close`** (or **`close --force`** only if you accept skipping gates). Successful **`close`** clears **`.popcorn-xp/.active-team`** (when it still names this team) and truncates **`context-store.log`**; run **`echo {team} > .popcorn-xp/.active-team`** again before the next slice. In each new **RETRO.md** entry, set **Lead host:** **`codex`** and **Task transport:** **`subagent`** (or **`team`** if you opted in) so future readers know which playbook and hooks applied — same fields as **`platforms/claude/popcorn-xp/skills/popcorn-xp/SKILL.md`** retro template.
- **Recovery:** After **two** failures on **session mechanics** for the **same drive seat** (claims, rotation, close-check), switch to a **bounded implementation worker** or a **fresh team** instead of retrying the same seat.

## 5. Claude plugin parity

The full Claude lead playbooks are **`platforms/claude/popcorn-xp/skills/popcorn-xp/SKILL.md`** (file-bus) and **`platforms/claude/popcorn-xp-team/skills/popcorn-xp-team/SKILL.md`** (Agent Teams) — not required on disk for this Codex-only bundle.
