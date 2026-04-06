## Role Roster

The plugin ships with agent definitions in `platforms/claude/__AGENTS_PKG__/agents/` that can be used as teammates. The default team is **3 core members**: **one driver, one navigator, one advisor** - **current, future, and past** respectively. The driver implements what is in flight now; the navigator reads ahead and steers; the advisor reviews what has already landed (verification, regressions, objections). Map concrete personas from `platforms/claude/__AGENTS_PKG__/agents/` onto those three seats. Add specialists for specific tasks; they are supplemental, not part of the core rotation unless you promote them.

**Core roles (coding tasks):**

| Agent | Lens | Standing work |
|-------|------|--------------|
| `popcorn-xp:craftsman` | "Is this clean and readable?" | Drive and navigate in rotation |
| `popcorn-xp:expert` | "Does this actually work in edge cases?" | Drive and navigate in rotation |
| `popcorn-xp:scout` | "Are we solving the right problem?" | **Default advisor:** log-watching through scope, constraints, and orientation — catch wrong surface, drift, and early unknowns |
| `popcorn-xp:tester` | "How will we prove this works?" | **Usually supplemental:** verification pairs, RED/GREEN lanes, final proof; **standing advisor** only when the session is verification-led |

The **navigator's** standing work is **read-ahead**: stay one step ahead of the driver — read files the driver hasn't reached yet, check constraints and patterns, publish a READY artifact before implementation starts.

The **advisor's** standing work is **log-watching**: read `.popcorn-xp/{team-name}/context-store.log` after every batch of edits, read the changed files through your lens, and send advice. The advisor does not rotate into driving unless they own an explicit task.

**Default the standing advisor to `scout`.** That lens stays on "right problem, right place, right constraints" for the whole session. Use `tester` as standing advisor when tests and proof are the main risk; otherwise pull `tester` in for specific verification tasks or bugfix lanes (see Monitor).

The `scout` agent also fits **orientation-first** work when the first task is "map the codebase" rather than "implement X" (driver or advisor).
The `strategist` agent is for planning-first sessions where the first task is "clarify the bet" rather than "start building."

**Supplemental roles (task-scoped, not part of core rotation):**

| Agent | Lens |
|-------|------|
| `popcorn-xp:strategist` | "Are we building the right thing, for the right people, in the right order?" |
| `popcorn-xp:service-designer` | "Does the interface serve the experience — from API contract to user interaction?" |
| `popcorn-xp:visual-designer` | "Does this look right and feel right?" |
| `popcorn-xp:qa` | "Does this work from the user's perspective?" |
| `popcorn-xp:product-manager` | "What problem are we solving, and is this the right way to solve it?" |

**Independent auditor (not a teammate):**

| Agent | Lens |
|-------|------|
| `popcorn-xp:code-reviewer` | "What does this code actually do, and can I prove it?" |

The code-reviewer is **not** part of the team. Do not spawn it with `team_name`. The lead launches it independently via the Agent tool at review checkpoints (see Monitor section) and relays its findings to the team.

The lens shapes how an agent thinks, not what it's allowed to do. Any teammate can drive, navigate, write tests, or review code. When rotating, prefer giving the driver role to whoever was just navigating — they carry context from watching the code emerge.

### Native Agent Mapping Reference

Native agents carry project-specific context, conventions, and tool configurations that popcorn-xp defaults lack — prefer them when the fit is clear. Use this table when mapping discovered agents to popcorn-xp personas during initialization (Step 2):

| If the agent's purpose is... | It aligns with... |
|---|---|
| Exploring codebases, mapping scope, finding constraints | **scout** |
| Implementing features, refactoring, clean code | **craftsman** |
| Correctness analysis, edge cases, invariants, auditing | **expert** |
| Writing/designing tests, running verification | **tester** |
| Planning, sequencing, positioning, roadmap tradeoffs | **strategist** |
| API design, service boundaries, contracts | **service-designer** |
| UI/UX design, visual patterns, accessibility | **visual-designer** |
| User flow validation, acceptance testing, E2E | **qa** |
| Requirements, prioritization, scope decisions | **product-manager** |
| Independent code review, evidence-based auditing | **code-reviewer** |

A native agent doesn't need to match perfectly — it needs to serve the same lens. A `flutter-architect` can fill the craftsman role for a Flutter project. An `elixir-phoenix-social` can fill the expert role for an Elixir service. A `code-scout` (or similar explore agent) maps to **scout** — **prefer for the standing advisor seat**. A `test-engineer` is a direct replacement for **tester** (verification lens).

**How to spawn a native agent as a teammate:**

Use the native agent's `subagent_type`. The native agent definition provides "how I think about this domain"; the popcorn-xp protocol provides "how I collaborate in a pair session."

Native agents don't have the protocol pre-loaded (only popcorn-xp agents do via the `skills` field). Instruct them to load it as their first action:

```
Agent(
  name: "test-engineer",
  subagent_type: "test-engineer",
  model: "{model}",
  team_name: "{team-name}",
  prompt: "You are a Popcorn XP teammate in session '{team-name}'.

           FIRST: Load the collaboration protocol by invoking:
             Skill('popcorn-xp-protocol')

           Role: test-engineer (filling tester persona)
           Lens: <use the native agent's own description as the lens>

           <driver/navigator/advisor assignment from protocol.md templates>
           <task context>"
)
```

The native agent's behavioral instructions (from its definition file) load automatically via `subagent_type`. The `Skill` invocation loads the collaboration protocol. The prompt adds role assignment and task context.

## Workflow
