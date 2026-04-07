
Read the frontmatter (`name`, `description`) of each discovered file. Also review the available `subagent_type` values from the system (these appear in the Agent tool's agent type list). Installed plugins register agents like `test-engineer`, `code-scout`, `flutter-architect`, etc.

**Present what's available.** Show the user all discovered agents alongside the popcorn-xp defaults, mapped to personas using the Native Agent Mapping Reference table. Let the user pick who's on the team:

> Here are the agents available for this session:
>
> | Persona | Available agents |
> |---------|-----------------|
> | scout | `popcorn-xp:scout`, `code-scout` (native) — **default standing advisor** |
> | craftsman | `popcorn-xp:craftsman`, `flutter-architect` (native) |
> | expert | `popcorn-xp:expert` |
> | tester | `popcorn-xp:tester`, `test-engineer` (native) — verification-led advisor or task-scoped proof |
> | strategist | `popcorn-xp:strategist` |
> | code-reviewer | `popcorn-xp:code-reviewer`, `code-reviewer` (native) |
>
> Which roles do you want on the team, and which agent for each? I'll spawn the initial three (driver, navigator, advisor) at the start and bring in supplemental specialists as specific tasks require them. **Unless you prefer a verification-led advisor, default advisor = scout** (or native `code-scout`).

Wait for the user to confirm before proceeding. The user picks:

- Which personas to include (driver, navigator, advisor at minimum; add supplemental specialists as needed)
- Which agent fills each slot (native or default)
- They can also request agents not in the list by name

Not every selected agent is spawned immediately. The lead spawns the initial three-agent team (driver, navigator, advisor) for the first task and brings supplemental specialists in as tasks require them. The full roster is the **bench** — agents the session may use — not a list of agents to launch all at once.

Store the confirmed roster. Note which personas are filled by native agents — this feeds the retro.
