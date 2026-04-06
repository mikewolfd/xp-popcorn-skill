# Dual-mode runtime: Codex companion

This document companions [dual-mode-proposal.md](./dual-mode-proposal.md). It records how OpenAI **Codex** (CLI / app) lines up with that proposal, using the repo’s snapshots under `research/official/codex/` as the reference. Upstream docs may move; treat those files as notes, not a live contract.

## Relationship to the main proposal

The proposal defines **product shape** (topology, artifacts, `subagent` vs `team`). On Codex, **only part of the runtime surface exists**. The **durable core** (session files, `shared/runtime/bin/session`, typed advice, closeout checks) stays valid. **Transport and hooks** must be translated, not copied from Claude Code.

## Mode mapping on Codex

| Proposal mode | On Codex |
|---------------|----------|
| **`team`** | **Not documented in the captured Codex references.** The repo's Codex snapshots document subagents and parent-driven multi-agent tools, but they do not document a Claude-style Agent Teams API (`TeamCreate`, `TaskUpdate`, `TeammateIdle`, `SendMessage`, `TeamDelete`) or a separate live peer-to-peer team transport. |
| **`subagent`** | **This is the natural Codex path.** Subagent workflows, custom agents under `.codex/agents/`, and (when enabled) multi-agent tools align with lead-orchestrated workers plus a file-backed task bus. |

**Practical stance:** Based on the captured Codex references, treat Codex as **`subagent`-mode-first** for Popcorn XP and do not assume a separate Codex-native `team` transport until it is documented.

## What Codex provides (relevant bits)

Summarized from `research/official/codex/subagents.md` and `research/official/codex/config.md`:

- **Subagents:** Spawn specialized agents, wait for results, consolidate. User explicitly asks for spawns; orchestration includes follow-up, stop, and close of threads (`/agent` in CLI).
- **Custom agents:** Project-scoped TOML in `.codex/agents/` with `name`, `description`, `developer_instructions`, and optional `model`, `sandbox_mode`, `mcp_servers`, `skills.config`, etc.
- **Limits:** `[agents] max_threads`, `max_depth` (default depth allows a direct child; deeper nesting is configurable).
- **Multi-agent tools (feature flag, on by default in reference):** `spawn_agent`, `send_input`, `resume_agent`, `wait_agent`, `close_agent` — parent-driven lifecycle, not the same as Agent Teams but usable for lead orchestration.

## Hooks on Codex vs the proposal

From `research/official/codex/hooks.md`:

**Available events (today in the snapshot):** `SessionStart`, `PreToolUse`, `PostToolUse`, `UserPromptSubmit`, `Stop`. Behind `features.codex_hooks = true`. Experimental; Windows disabled in the doc.

**Important gaps relative to Claude-oriented text in [dual-mode-proposal.md](./dual-mode-proposal.md) § “Subagent Runtime Constraints”:**

- There is **no documented `SubagentStart` / `SubagentStop`** hook event. Lifecycle gates that Claude would hang off subagent stop need another trigger (for example **`Stop`** on the relevant session thread, **`UserPromptSubmit`**, or **`shared/runtime/bin/session`**-centric checks).
- **`PreToolUse` / `PostToolUse` matchers apply to tool names; the snapshot states the runtime only emits `Bash` for those events.** You cannot rely on hook matchers for arbitrary non-Bash tools the way Claude Code hook tables describe for edits/reads.
- Hooks receive **`session_id`**, **`cwd`**, **`transcript_path`**, etc., and the hook input defines `session_id` as the current **session or thread id**. The doc does **not** spell out a separate hook configuration per subagent thread. The safest assumption is **shared hook configuration files with per-session/per-thread invocations**, not Claude-style subagent-specific hook packs.

**Correction for Codex readers:** Ignore, for Codex, the proposal bullets that assume **subagent-scoped hook packs** and **`SubagentStop`** as stable platform facts. Replace them with **shared hooks + `shared/runtime/bin/session` + agent instructions**.

## Shared core (unchanged)

Everything in the proposal about **durable artifacts** and **`shared/runtime/bin/session` as the write API** applies on Codex:

- `LOG.md`, `ADVICE.md`, `RETRO.md`, `agent-state/`, task bus under `tasks/T{n}/`, and closeout via `close-check` / `close`.

Implementation work is **portable bash and conventions**; Codex does not need special APIs for the file bus.

## Skills and prompts: layer transport, don’t fork the product

Popcorn XP has **one product model** (pairing, typed advice, durable files) and **two transports** (`team` vs `subagent`). On Codex you are effectively **subagent-only** for native transport, but the **documentation and prompt packaging** should still follow the same layering the Claude plugin is moving toward — so nothing drifts into two incompatible “products.”

### Principles

1. **Single lead entrypoint.** One place the human (or lead agent) starts from — mode choice, session setup, closeout checklist. On the Claude plugin that is `platforms/claude/subagent/skills/popcorn-xp/SKILL.md`; on Codex, one “orchestrator” skill or a fixed block in the lead’s **`developer_instructions`** that always names the mode and points at the right transport section. Do **not** split into two unrelated top-level entrypoints unless you add an explicit **router** skill that stays canonical.

2. **Split teammate *transport*, not philosophy.** Keep **one shared core**: OBJECTION / SMELL / STEER / FYI, `ADVICE.md` vs task chat, `LOG.md`, rotation *intent*, retro/shutdown discipline. Put **mode-specific** content only where verbs differ:

   | Layer | Team transport | Subagent transport (Codex-aligned) |
   |-------|----------------|--------------------------------------|
   | Checkpoints | `SendMessage`, `session log`, context-store cadence | `session chat`, `session log`, `cursor-ack` for navigators in `waiting_on_driver` |
   | Claims / lock | `TaskUpdate`, team hooks | `session task-claim` / `task-release` / `task-complete`, optional `task-revision` CAS |
   | Advisor awareness | `context-store.log` + `session review` | `tasks/T{n}/back-forth.md` + `session review` |
   | Idle / stop gates | `TeammateIdle`, `SubagentStop` (Claude) | Lead wake-ups; **`Stop` hook** + `shared/runtime/bin/session` checks (Codex) |

3. **Two ways to package the teammate protocol (pick one per repo):**

   - **A — Two thin supplements:** e.g. team vs subagent fragments (markdown or Codex skills) that **both** open with the **same** short “Core rules” block, then diverge only in a “Transport” section. Lowest risk of reading the wrong SendMessage example in subagent mode.

   - **B — One protocol with two top-level sections:** a single `SKILL.md`-style doc headed **Team transport** and **Subagent transport**, with shared core above or inlined once. Easier for a single `skills.config` pointer, slightly easier to skim wrong if sections blur together.

   In the Claude repo, the long-form templates live in `shared/protocol/templates.md` (shared + mode-specific addenda); the auto-loaded teammate skill is `platforms/claude/subagent/skills/popcorn-xp-protocol/SKILL.md`. A Codex port should **mirror that shape**: either two small skills under `skills.config` or one skill with two clear sections — not interleaved “subagent:” footnotes on every bullet.

4. **Reference implementation stays bash-first.** `shared/runtime/bin/session` and hook scripts are the contract; prompts only **describe** how to call them. Codex uses the same shared shell logic — it does not redefine closeout or advice semantics in prose.

### Mapping to Codex project files

| Concern | Suggested shape |
|---------|-----------------|
| Shared core (both modes) | One markdown file or skill: advice types, file boundaries, closeout intent |
| Subagent transport only | Second file, or a titled section in the same skill: `task-init`, `chat`, `cursor-ack`, `close-check`, `close` |
| Per-role agents | `.codex/agents/*.toml` — **`developer_instructions`** should **import by reference** (“follow § Subagent transport in …”) instead of duplicating the full protocol twice across driver/navigator/advisor |
| Lead | Same repo’s orchestrator doc/skill; mode line + pointer to transport section |

This matches **“subagent-mode-first on Codex”** above: your **default** packaged path is the **subagent transport** layer plus shared core; **team transport** text exists for parity with the Claude plugin and for anyone running both products, not because Codex exposes Agent Teams today.

## Reasonable enforcement (not over-built)

A minimal, maintainable stack on Codex:

1. **`developer_instructions`** in each custom agent TOML: keep them **short** and point at the packaged **shared core** + **subagent transport** (see [Skills and prompts: layer transport, don’t fork the product](#skills-and-prompts-layer-transport-dont-fork-the-product)) instead of duplicating prose — require typed advice in `ADVICE.md`, task chat in `back-forth.md`, state via `shared/runtime/bin/session`, and explicit closeout discipline.
2. **`SessionStart`** with `matcher` `startup|resume`: if an active Popcorn session exists for the repo, inject **`additionalContext`** (short reminder of session path and rules).
3. **`Stop` hook, gated in script** (for example by inspecting `cwd` or `.popcorn-xp/.active-team` inside the hook handler): run the same **unresolved OBJECTION** / **`close-check`** logic you already trust, so turns do not “finish clean” against broken invariants when you choose to enforce. `Stop` does not honor `matcher`, so the filter has to live in the hook code.

**Usually skip at first:** broad `PreToolUse` Bash allowlists (bypassable, noisy), duplicate logic on `UserPromptSubmit`, external watchers unless you need alerting for other reasons.

## Configuration layout (Codex)

Typical check-in pattern for a project that runs Popcorn XP on Codex:

- `.codex/config.toml` — `[features] codex_hooks = true`, `[agents]` limits as needed.
- `.codex/hooks.json` — `SessionStart` / `Stop` (and optional `PreToolUse` / `PostToolUse` only if you have a concrete, narrow policy).
- `.codex/agents/*.toml` — driver, navigator, advisor (or mapped names). Prefer **short** `developer_instructions` that point at one or two packaged skills/files (**shared core** + **subagent transport**), per [Skills and prompts: layer transport, don’t fork the product](#skills-and-prompts-layer-transport-dont-fork-the-product) — avoid pasting divergent full protocols into three TOML files.

Popcorn XP’s Claude source tree (`platforms/claude/subagent/`) remains the source for **team mode** and for **reference hook scripts**; a Codex port **reuses or adapts shell logic** and **does not assume** the same hook event names or tool matchers.

### Reference layout in this repository (implemented)

The popcorn-xp repo ships a **copy-paste / merge** layout you can drop into another project (with `shared/runtime/bin/session` and `platforms/codex/subagent/hooks/` vendored alongside):

| Path | Purpose |
|------|---------|
| [`.codex/config.toml`](../../.codex/config.toml) | Enables `codex_hooks`, sets `[agents]` defaults |
| [`.codex/hooks.json`](../../.codex/hooks.json) | `SessionStart` → [`platforms/codex/subagent/hooks/codex-session-start.sh`](../../platforms/codex/subagent/hooks/codex-session-start.sh); `Stop` → [`platforms/codex/subagent/hooks/codex-stop-advice.sh`](../../platforms/codex/subagent/hooks/codex-stop-advice.sh) |
| [`platforms/codex/subagent/skills/popcorn-xp-protocol-core/`](../../platforms/codex/subagent/skills/popcorn-xp-protocol-core/SKILL.md) | Layer A — shared core |
| [`platforms/codex/subagent/skills/popcorn-xp-protocol-subagent/`](../../platforms/codex/subagent/skills/popcorn-xp-protocol-subagent/SKILL.md) | Layer B — subagent transport |
| [`platforms/codex/subagent/LEAD-WORKFLOW.md`](../../platforms/codex/subagent/LEAD-WORKFLOW.md) | Vendored lead checklist (no dependency on `skills/popcorn-xp/`) |
| [`platforms/codex/subagent/COMPANION.md`](../../platforms/codex/subagent/COMPANION.md) | Vendored hook / project-root notes |
| [`.codex/agents/`](../../.codex/agents/) | Example agents with `[[skills.config]]` pointing at the two skills |
| [`platforms/codex/subagent/README.md`](../../platforms/codex/subagent/README.md) | Install notes and assumptions |

Hook **commands** in `hooks.json` use `$(git rev-parse --show-toplevel)` so the path resolves from the **current shell cwd** when Codex expands the command. **Inside** the hook handlers, stdin **`cwd`** (often a repo **subdirectory**) is mapped to **`CLAUDE_PROJECT_DIR`** via **`git -C "$cwd" rev-parse --show-toplevel`**, with fallback to **`cwd`** when not in a git work tree — so **`.popcorn-xp`** is found at the **repository root** even when the session cwd is nested. Vendor [`shared/runtime/lib/resolve-project-dir.sh`](../../shared/runtime/lib/resolve-project-dir.sh) alongside the other shared runtime helpers; **`shared/runtime/bin/session`** uses the same resolver when **`CLAUDE_PROJECT_DIR`** is unset.

Regression tests: **`CX-*`** cases in [`tests/test-hooks.sh`](../../tests/test-hooks.sh).

## Non-goals on Codex

- **Parity with `team` mode** without a Codex-native team transport.
- **Mechanical idle semantics** equivalent to `TeammateIdle`; use lead wake-ups, resume tools, and file cursors as in the proposal.
- **Assuming** per-subagent hook isolation or `SubagentStop` until documented for your target Codex release.

## References

- [dual-mode-proposal.md](./dual-mode-proposal.md) — full product proposal.
- [shared/protocol/core.md](../../shared/protocol/core.md) and [shared/protocol/templates.md](../../shared/protocol/templates.md) — long-form teammate templates (shared core + mode-specific addenda); mirror this layering in Codex-packaged skills.
- `research/official/codex/subagents.md` — subagents and custom agents.
- `research/official/codex/hooks.md` — hook events and limitations.
- `research/official/codex/config.md` — `features.multi_agent`, `features.codex_hooks`, and other keys.
