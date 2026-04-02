Built-In Agent Types
Report Issue
12 min
Level: Advanced
Claude Code ships with a curated set of built-in sub-agents that the main agent can spawn via the Agent tool. Each built-in agent occupies a distinct niche in the agentic workflow—ranging from fast read-only search to adversarial verification—and is gated behind a layered system of compile-time feature flags, runtime GrowthBook experiments, and environment variables. This page catalogs every built-in agent, its behavioral contract, its tool permissions, and the conditions under which it becomes available.

Agent Definition Architecture
All agents—built-in, custom, and plugin—conform to the BaseAgentDefinition interface declared in loadAgentsDir.ts. Built-in agents extend this with the BuiltInAgentDefinition variant, which carries source: 'built-in', baseDir: 'built-in', and a dynamic getSystemPrompt() factory instead of a static systemPrompt string (loadAgentsDir.ts). This factory pattern allows built-in agents to inject runtime contextâe user's MCP server list, custom skills, or settings—into their prompts at spawn time.





















The getBuiltInAgents() function in builtInAgents.ts assembles the final list through a sequence of conditional branches: SDK users in non-interactive mode can suppress all built-ins via CLAUDE_AGENT_SDK_DISABLE_BUILTIN_AGENTS; coordinator mode replaces the entire set with its own worker agents; otherwise, a baseline of two agents is always present, with additional agents appended based on feature flags and GrowthBook experiment values.

Sources: builtInAgents.ts, loadAgentsDir.ts

Feature Gate Topology
Not every built-in agent is available in every session. The activation logic uses a three-tier gating strategy that balances experimentation with operational stability.





















The gate hierarchy resolves from most restrictive to least. The coordinator mode check uses a lazy require() to avoid circular dependencies at module init time (builtInAgents.ts). GrowthBook values are accessed tough the _CACHED_MAY_BE_STALE accessor, which tolerates mid-session gate flips without Zod rejection errors—a trade-off documented in AgentTool.tsx.

Sources: builtInAgents.ts, AgentTool.tsx

Complete Agent Catalog
The following table provides a consolidated reference of all six built-in agent definitions, their behavioral properties, and activation conditions.

Agent	agentType	Model	Tool Access	Permission Mode	Color	Special Flags	Activation
General Purpose	general-purpose	inherit (parent)	All tools (*)	inherits parent	—	—	Always
Explore	Explore	haiku (external) / inherit (ant)	Read-only subset	inherits parent	—	omitClaudeMd: true	Feature gate
Plan	Plan	inherit	Read-only subset	inherits parent	—	omitClaudeMd: true	Feature gate
Verification	verification	inherit	Read-only + /tmp writes	inherits parent	red	background: true, criticalSystemReminder	Feature gate
Claude Code Guide	claude-code-guide	haiku	Web/search + read	dontAsk	—	Dynamic context injection	Non-SDK only
Statusline Setup	statusline-setud, Edit only	inherits parent	orange	—	Always
Sources: builtInAgents.ts, constants.ts

General Purpose Agent
The default fallback agent for multi-step tasks. It has unrestricted tool access via tools: ['*'] and no model override, inheriting whatever model the parent agent is using (generalPurposeAgent.ts). Its system prompt establishes a concise behavioral contract: complete the task fully without gold-plating, search broadly before narrowing, prefer editing existing files over creating new ones, and never proactively generate documentation files. The prompt ends by instructing the agent to return a concise report—the parent relays this summary to the user.

This agent occupies the catch-all position in the dispatch hierarchy. When no specialized agent matches the task characteristics, the LLM falls back to spawning a general-purpose sub-agent.

Sources: generalPurposeAgent.ts

Explore Agent
A fast, read-only search specialist gated behind the BUILTIN_EXPLORE_PLAN_AGENTS compile-time feature and the tengber_stoat GrowthBook experiment (builtInAgents.ts). The Explore agent uses haiku on external builds (for speed) and inherit on ant-native builds where the GrowthBook tengu_explore_agent flag is checked at runtime (exploreAgent.ts).

Its tool access is defined by a disallow list rather than an allow list. The agent explicitly cannot use Agent, ExitPlanMode, FileEdit, FileWrite, or NotebookEdit (exploreAgent.ts). This constraint enforces the read-only invariant at the tool-permission level. The omitClaudeMd: true flag strips project-level CLAUDE.md context from the sub-agent's prompt, saving tokens since the main agent already has full project conventions and can interpret the explore results in context (exploreAgent.ts).

The system prompt includes adaptive guidance for ant-native builds: when hasEmbeddedSearchTools() is true, Glob/Grep are unavailable and the agent is directed to use find/grep via Bash instead (exploreAgent.ts).

One-shot optimization: Explore and Plan are both registered in ONE_SHOT_BUILTIN_AGENT_TYPES (constants.ts), which suppresses the agentId/SendMessage trailer in the tool result. This saves approximately 135 characters per invocation—meaningful at the scale of ~34M Explore runs per week as noted in the source comment.

Sources: exploreAgent.ts, constants.ts

Plan Agent
A read-only software architect that shares the same disallow list as the Explore agent (planAgent.ts). Unlike Explore, Plan uses model: 'inherit' unconditionally and inherits the Explore agent's tool list via tools: EXPLORE_AGENT.tools (planAgent.ts).

The Plan agent's system prompt defines a structured four-phase process: understand requirements, explore the codebase thoroughly, design a solution considering trade-offs, and produce a detailed implementation plan. The required output format mandates a "Critical Files for Implementation" section listing 3–5 files (planAgent.ts). Like Explore, it sets omitClaudeMd: true to save context window space, but the comment notes that the agent can still read CLAUDE.md directly FileRead if it needs project conventions (planAgent.ts).

Plan is similarly gated behind the same BUILTIN_EXPLORE_PLAN_AGENTS / tengu_amber_stoat flags as Explore (builtInAgents.ts).

Sources: planAgent.ts

Verification Agent
An adversarial verification specialist gated behind the VERIFICATION_AGENT compile-time feature and the tengu_hive_evidence GrowthBook experiment (builtInAgents.ts). This is the most defensively prompted built-in agent, designed specifically to resist two failure patterns the system has identified: verification avoidance (reading code instead of running it, then writing "PASS") and being seduced by the first 80% (passing based on surface polish while missing broken functionality).

The agent enforces a strict read-only invariant for project files but explicitly permits writing ephemeral test scripts to /tmp or $TMPDIR via Bash (verificationAgent.ts). Its system prompt includes a comprehensive verification strategy matrix covering ten change types (frontend, backend/API, CLI, infrastructure, library, bug fix, mobile, data/ML pipeline, database migrations, and refactoring), each with specific procedural guidance (verificationAgent.ts).

The output format is rigidly enforced: every check must include a "Command run" block with exact commands and observed output. Reports without command evidence are explicitly rejected as invalid (verificationAgent.ts). The agent must terminate with a machine-parseable verdict line: VERDICT: PASS, VERDICT: FAIL, or VERDICT: PARTIAL (verificationAgent.ts).

Three properties distinguish this agent from the read-only search agents: background: true (runs asynchronously without blocking the parent), color: 'red' (for UI differentiation), and criticalSystemReminder_EXPERIMENTAL (an additional system reminder appended at a separate prompt position for emphasis) (verificationAgent.ts).

Sources: verificationAgent.ts

Claude Code Guide Agent
A documentation retrieval agent that answers user questions about Claude Code, the Claude Agent SDK, and the Claude API. It is excluded from SDK entrypoints (sdk-ts, sdk-py, sdk-cli) since SDK consumers don't need CLI guidance (builtInAgents.ts).

The Guide agent uses model: 'haiku' for fast response and permissionMode: 'dontAsk' to avoid permission prompts on web fetches and searches (claudeCodeGuideAgent.ts). Its tool set is split into two configurations based on the build target: ant-native builds replace Glob/Grep with Bash (using embedded bfs/ugrep), while external builds include the dedicated Glob and Grep tools alongside WebFetch and WebSearch (claudeCodeGuideAgent.ts).

The Guide agent's system prompt is dynamically constructed via getSystemPrompt() rather than a static closure. It receives the toolUseContext parameter and injects four contextual sections at spawn time: custom skills from the project, custom agents from .claude/agents/, configured MCP servers, and the user's settings.json (claudeCodeGuideAgent.ts). This allows the agent to proactively suggest features the user has configured but may not know about. The feedback channel is conditional: 3P service users (Bedrock/Vertex/Foundry) are directed to file issues rather than using the /feedback command (claudeCodeGuideAgent.ts).

Sources: claudeCodeGuideAgent.ts

Statusline Setup Agent
A narrow-purpose agent for configuring the Claude Code terminal status line. It has the most restrictive tool access of any built-in agent: only Read and Edit (statuslineSetup.ts). It uses model: 'sonnet' and color: 'orange' (statuslineSetup.ts).

The agent's system prompt is a detailed procedural guide covering PS1-to-statusline conversion (with a complete escape sequence mapping table), the JSON stdin schema for the statusline command (documenting session metadata, context window percentages, rate limits, vim mode, agent info, and worktree state), and instructions for updating ~/.claude/settings.json (statuslineSetup.ts). It is one of only two always-available built-in agents alongside General Purpose (builtInAgents.ts).

Sources: statuslineSetup.ts

Tool Permission Patterns
Built-in agents use two complementary strategies to constrain their tool access, reflecting their different trust levels and operational scopes.









Allowlist agents explicitly enumerate which tools they can use. The general-purpose agent is the exception with tools: ['*'], granting full access. The statusline-setup agent takes the opposite extreme with only Read and Edit. The code guide agent occupies the middle ground with five targeted tools for web retrieval and local file inspection.

Denylist agents declare what they cannot use rather than what they can. All three read-only agents (Explore, Plan, Verification) share an identical disallow list: Agent, ExitPlanMode, FileEdit, FileWrite, and NotebookEdit. This blocks recursive agent spawning and all file-mutation tools. They implicitly have access to everything else—including Bash (for read-only commands),ileRead, search tools, and any MCP tools configured in the session.

The denylist pattern means read-only agents can still access MCP tools (e.g., mcp__playwright__*, mcp__claude-in-chrome__*) if they're configured. The verification agent's prompt explicitly instructs it to check for available MCP tools rather than assume their absence (verificationAgent.ts).

Sources: generalPurposeAgent.ts, exploreAgent.ts, planAgent.ts, verificationAgent.ts, claudeCodeGuideAgent.ts, statuslineSetup.ts

Relationship to the Wider Agent Ecosystem
Built-in agents are one of three agent definition sources, alongside custom agents (from .claude/agents/ directories, user settings, and project settings) and plugin agents (loaded from registered plugins). All three types resolve through the unified getAgentDefinitionsWithOverrides() function in loadAgentsDir.ts, which merges, deduplicates, and validates the complete agent pool. Custom agents can override built-in agents by sharing the same agentType string, and the filterDeniedAgents() utility at AgentTool.tsx enforces permission-level deny rules at dispatch time.

For understanding how the main agent selects and dispatches to these built-in types, see Agent Tool and Sub-Agent Spawning. For the multi-agent coordination layer that can replace built-in agents entirely in coordinator mode, see Coordinator Mode. For how custom agents extend or override the built-in set, see Plugin and Skill System.
