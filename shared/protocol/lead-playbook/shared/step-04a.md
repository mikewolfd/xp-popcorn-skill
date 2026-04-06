### 4. Spawn Teammates

Spawn the initial three-agent team from the roster confirmed in Step 2: one driver, one navigator, and one advisor. All three start simultaneously. The driver and navigator cover the first task pair; the advisor begins log-watching immediately and sends advice from the first checkpoint onward.

You don't need to launch the entire bench on the first task — supplemental specialists join when their task pair is assigned. Pull from the bench when the work calls for a different lens or when rotation calls for a fresh agent.

**Always pass `model: "{model}"` when spawning teammates** (using the model chosen in Step 2), including native agents. Native agent definitions may inherit a different model from their definition file — the explicit `model` parameter overrides that.

For each persona slot, use the agent the user selected in Step 2. When using a native agent, pass its `subagent_type` so its domain-specific instructions load automatically.

**Example: all defaults (no native agents found)**

```
Agent(
  name: "craftsman",
  model: "{model}",
  team_name: "{team-name}",
  prompt: "<driver coordinator prompt from protocol.md>"
)
```

**Example: native agent filling a persona slot**

```
Agent(
  name: "test-engineer",
  subagent_type: "test-engineer",
  model: "{model}",
  team_name: "{team-name}",
  prompt: "You are a Popcorn XP teammate in session '{team-name}'.
           FIRST: Load the protocol: Skill('popcorn-xp-protocol')
           Role: test-engineer (filling tester persona)
           Lens: <native agent's description>
           <driver/navigator assignment + task context>"
)
```

**Example: mixed team (native + defaults)**

```
# Native flutter-architect fills craftsman — loads protocol via Skill tool
Agent(name: "flutter-architect", subagent_type: "flutter-architect",
  model: "{model}", team_name: "{team-name}",
  prompt: "FIRST: Skill('popcorn-xp-protocol')\n<driver prompt, lens from native agent>")

# Default expert — protocol auto-loaded via skills field
Agent(name: "expert", model: "{model}", team_name: "{team-name}",
  prompt: "<navigator prompt from protocol.md>")

# Default scout as standing advisor — protocol auto-loaded via skills field
Agent(name: "scout", model: "{model}", team_name: "{team-name}",
  prompt: "<advisor prompt from protocol.md>")

# Or native code-scout as advisor — loads protocol via Skill tool
Agent(name: "code-scout", subagent_type: "code-scout",
  model: "{model}", team_name: "{team-name}",
  prompt: "FIRST: Skill('popcorn-xp-protocol')\n<advisor prompt, lens from native agent>")
```

