# Popcorn XP — lead workflow (Codex / subagent)

Vendored lead reference for **OpenAI Codex** with the `codex/` + `.codex/` layout. **Default `subagent` mode** (file bus). For hook behavior and project-root resolution, see **`codex/COMPANION.md`**.

## 1. Session setup

1. Pick a short team name (e.g. `fix-auth`).
2. Create **`.popcorn-xp/{team}/`**, **`LOG.md`**, **`ADVICE.md`**, and a **`session`** wrapper that **`exec`**s your vendored **`bin/session`** (see plugin `bin/session` in popcorn-xp).
3. **`echo {team} > .popcorn-xp/.active-team`**
4. **`printf 'subagent\n' > .popcorn-xp/{team}/.runtime-mode`** (or omit **`.runtime-mode`** if your **`bin/session`** defaults to subagent).
5. Spawn **three** teammates (driver, navigator, advisor) with **`codex/skills/...`** wired via **`[[skills.config]]`** in **`.codex/agents/*.toml`**.
6. Preferred Codex teammate defaults: `model="gpt-5.4-mini"` with `reasoning_effort="xhigh"` for normal pair work; escalate to `model="gpt-5.4"` with `reasoning_effort="medium"` when the slice is broader or repeated recovery suggests the cheaper path is false economy.

## 2. Tasks and pairing

- Each logical slice is a **pair**: **drive** + **navigate** task (navigator verifies after driver completes).
- **`session task-init {n}`** before work on task **n**.
- **`session task {n}`** for a **LOG.md** placeholder; real driver/navigator lines sync from **`task-claim`** / **`task-release`**.
- Claims: **`session task-claim`**, **`task-release`**, **`task-complete`**, **`task-abandon`** as in **`popcorn-xp-protocol-subagent`**.
- Typed advice only in **`ADVICE.md`** (**`session advice`** / **`session resolve`**). **OBJECTION** blocks completion until resolved.

## 3. Chat and cursors (subagent)

- Tactical: **`session chat`** / **`session chat-read`** on **`tasks/T{n}/back-forth.md`**.
- Navigators in **`waiting_on_driver`**: keep **`cursor-ack`** current.
- Advisors: **`session review`** to advance review cursors when required.

## 4. Health and closeout

- Run **`session health`** (or **`--strict`**) before risky handoffs.
- **`session retro-request`** → per-agent **`.retro-*.md`** or **`handoff-*.md`** as required.
- **`session close-check`** → append **`RETRO.md`** (≥5 real lines) → **`session close`** (or **`close --force`** only if you accept skipping gates). Successful **`close`** clears **`.popcorn-xp/.active-team`** (when it still names this team) and truncates **`context-store.log`**; run **`echo {team} > .popcorn-xp/.active-team`** again before the next slice. In each new **RETRO.md** entry, set **Lead host:** **`codex`** and **Task transport:** **`subagent`** (or **`team`** if you opted in) so future readers know which playbook and hooks applied — same fields as **`skills/popcorn-xp/SKILL.md`** retro template.
- **Recovery:** After **two** failures on **session mechanics** for the **same drive seat** (claims, rotation, close-check), switch to a **bounded implementation worker** or a **fresh team** instead of retrying the same seat.

## 5. Claude plugin parity

The full lead playbook (team vs subagent, native Agent Teams, coordinator mode) is **`skills/popcorn-xp/SKILL.md`** in the **Claude Code plugin** tree — not required on disk for this Codex-only bundle.
