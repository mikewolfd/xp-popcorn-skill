### 2. Create the Team

**Choose the teammate model.** Ask the user which model to use for teammates:

> What model should I use for the teammates? Options:
>
> - **haiku** — fastest and cheapest, good default for most tasks
> - **sonnet** — more capable, better for complex reasoning
> - **opus** — most capable, slower and more expensive
>
> (Default: haiku)

Store their choice as `{model}` and pass it to every `Agent(model: ...)` call when spawning teammates. If the user doesn't have a preference, default to `haiku`.

**Pick the team.** Scan for available agents, map them to personas, and let the user draft the roster.

**Scan for agents:**

