Deep Dive
Agent Tool and Sub-Agent Spawning
Report Issue
12 min
Level: Advanced
The Agent tool is the delegation primitive of Claude Code — it enables the LLM to spawn specialized sub-agents that execute tasks in parallel or in isolation, then return structured results to the parent conversation. This page covers the tool's architecture, the three distinct spawn paths (synchronous, async, and teammate), the fork subagent experiment for prompt cache optimization, worktree-based filesystem isolation, and the permission model that governs tool access across agent boundaries.

Architectural Overview
The Agent tool sits at the intersection of the tool system and the multi-agent runtime. When the LLM emits a tool_use block targeting the Agent tool, the call() method in AgentTool.tsx evaluates the input parameters and routes to one of three spawn paths. Each path shares a common substrate — the runAgent() async generator in runAgent.ts — but differs in lifecycle management, concurrency model, and UI su


























Input Schema and Spawn Path Routing
The tool's input schema is defined lazily via lazySchema() in AgentTool.tsx, combining a base schema with optional multi-agent parameters and isolation fields. The base schema accepts four core fields: description, prompt, subagent_type, and model. When the KAIROS feature flag is active, additional fields name, team_name, and mode enable teammate spawning, while isolation and cwd control filesystem scoping.

Sources: AgentTool.tsx

Parameter	Type	Purpose
description	string (required)	Short 3–5 word label for UI display and task tracking
prompt	string (required)	Task directive for the agent to execute
subagent_type	string (optional)	Selects a specialized agent definition; omitting triggers fork path when enabled
model	'sonnet' | 'opus' | 'haiku'	Overrides the agent's model; inherits parent if omitted
run_in_background	boolean	Requests async execution; forcibly omitted when fork or background tasks are disabled
name	string	Addressable name for SdMessage routing; triggers teammate spawn when combined with team_name
team_name	string	Team roster context; defaults to current team context
mode	PermissionMode	Permission mode for spawned teammate (e.g., "plan")
isolation	'worktree' | 'remote'	Filesystem isolation mode
cwd	string	Absolute working directory override (KAIROS-gated, mutually exclusive with worktree isolation)
The routing logic in call() at AgentTool.tsx checks for teammate spawn first: if both team_name (resolved or provided) and name are present, execution delegates to spawnTeammate(). Otherwise, the subagent_type resolution determines whether the fork experiment path or the standard typed-agent path executes.

Sources: AgentTool.tsx, AgentTool.tsx

The Three Spawn Paths
Synchronous Sub-Agent
Synchronous execution blocks the parent agent's turn until the sub-agent completes. The call() method at AgentTool.tsx creates an agentId, registers a foreground task via registerAgentForeground(), then iterates the runAgent() async generator within a race against a background-promotion signal. The foreground task is registered immediately so it can be promoted to background at any point via backgroundAll().

Key implementation detail: a single backgroundPromise is created outside the iteration loop at AgentTool.tsx to avoid accumulating .then() callbacks on every iteration. When Promise.race() selects the background signal, the iterator is cleaned up and a new runAgent() invocation continues the agent's work as a background task.

Sources: AgentTool.tsx, AgentTool.tsx

Async Sub-Agent
When run_in_background is true, the agent definition has background: true, coordinator mode is active, the fork experiment is enabled, or KAIROS assistant mode is on, the agent runs asynchronously. The call() method at AgentTool.tsx registers the agent via registerAsyncAgent(), creates an agent-context wrapper for analytics attribution via runWithAgentContext(), then fires runAsyncAgentLifecycle() as a detached void promise. The parent immediately returns an async_launched status with the agent's ID and output file path.

The async lifecycle in agentToolUtils.ts handles the full agent execution, progress tracking, result finalization, worktree cleanup, and notification enqueuing. When enabled, background summarization via startAgentSummarization() provides periodic progress snapshots for the SDK.

Sources: AgentTool.tsx, AgentTool.tsx

Teammate Spawn
Teammate spawning is triggered when both name and team_name are present, delegating to spawnTeammate() in spawnMultiAgent.ts. This module manages three backend strategies: in-process teammates (same Node.js process via AsyncLocalStorage), tmux split-pane teammates (shared terminal with tiled pane layout), and iTerm2 split-pane teammates. The handleSpawn() function at spawnMultiAgent.ts performs backend detection, falling back to in-process if pane-based backends fail.

Teammates are registered as background tasks (even in-process ones) and receive their own task IDs. Out-of-process teammates get a tmux session, window name, and pane ID for interactive terminal display. The spawn result returns a teammate_spawned status with pane identifiers and metadata.

Sources: spawnMultiAgent.ts, spawnMultiAgent.ts, spawnMultiAgent.ts

Fork Subagent Experiment
The fork subagent, defined in forkSubagent.ts, is a performance optimization that exploits prompt cache sharing between parent and child agents. When the fork feature gate is active and subagent_type is omitted from the Agent tool call, the fork path fires instead of the default general-purpose agent.

The FORK_AGENT definition specifies permissionMode: 'bubble' and inherits the parent's full conversation context. The key insight is in AgentTool.tsx: the fork child receives the parent's rendered system prompt and parent's exact tool array (via useExactTools: true), producing byte-identical API request prefixes that hit the parent's prompt cache. A recursive fork guard at forkSubagent.ts detects the fork boilerplate tag in conversation history to prevent nested forking.

Prompt messages are constructed via buildForkedMessages() at forkSubagent.ts, which clones the parent's last assistant message (including all tool_use blocks), inserts placeholder tool_results (identical across all fork children for cache sharing), and appends the per-child directive as a user message.

Sources: forkSubagent.ts, AgentTool.tsx, forkSubagent.ts, forkSubagent.ts

Fork vs. Typed Agent tradeoff: Fork agents share the parent's prompt cache but cannot select a different model — model is explicitly ignored on the fork path because a different model breaks cache compatibility. Typed agents with subagent_type start fresh with zero ctext but can use any model. The prompt guidance in prompt.ts instructs the LLM to fork for research/implementation work where intermediate tool output is disposable, and to use typed agents for independent analysis requiring full briefing.

runAgent Execution Loop
The runAgent() async generator in runAgent.ts is the shared execution substrate for all non-teammate spawn paths. It accepts a comprehensive parameter object including agent definition, prompt messages, tool use context, permission callbacks, and optional overrides for fork-mode cache alignment.

Internally, runAgent() performs several critical setup steps: it initializes agent-specific MCP server connections via initializeAgentMcpServers() at runAgent.ts, resolves the agent's tool pool through resolveAgentTools() (or inherits the parent's pool directly in fork mode via useExactTools), builds the system prompt with environment details, registers Perfetto tracing spans, and writes session metadata to disk.

The generator then yields messages from the query() loop — the same core LLM interaction loop used by the main REPL. Each yielded message is typed and can be an assistant message, user message, progress message, osystem compact boundary. A filterIncompleteToolCalls() function at runAgent.ts sanitizes orphaned tool uses before they reach the API.

Sources: runAgent.ts, runAgent.ts, runAgent.ts

Tool Resolution and Permission Isolation
Each sub-agent receives an independently assembled tool pool, computed in call() at AgentTool.tsx via assembleToolPool() with the agent's own permission mode. This prevents the parent's tool restrictions from leaking into the child, and vice versa. The resolveAgentTools() function in agentToolUtils.ts further refines the pool based on the agent definition's tool allowlist/denylist, with wildcard expansion (['*']) and special handling for the Agent tool itself (which carries allowedAgentTypes metadata when specified as Agent(type1, type2)).

The filterToolsForAgent() function at agentToolUtils.ts applies global disallow lists: ALL_AGENT_DISALLOWED_TOOLS strips dangerous tools from all agents, CUSTOM_AGENT_DISALLOWED_TOOLS adds restrictions for non-built-in agents, and ASYNC_AGENT_ALLOWED_TOOLS further restricts background agents. MCP tools (mcp__ prefix) always pass through.

Sources: AgentTool.tsx, agentToolUtils.ts, agentToolUtils.ts

Worktree Isolation
When isolation: 'worktree' is set (either explicitly or via the agent definition's isolation field), call() at AgentTool.tsx creates a temporary git worktree via createAgentWorktree(), using a slug derived from the agent ID. The worktree path is injected into the agent's cwd via runWithCwdOverride(), and a worktree notice is appended to fork children's prompt messages explaining path translation requirements.

Cleanup logic at AgentTool.tsx runs after agent completion: hook-based worktrees are always kept, while git-based worktrees are removed if no changes were detected (via hasWorktreeChanges()). Worktrees with modifications are preserved, and their path is included in the completion notification so the parent can inspect or merge changes.

Sources: AgentTool.tsx, AgentTool.tsx

Output Schema and Result Types
The output schema in AgentTool.tsx is a discriminated union of two public types and two internal (dead-code-eliminated) types:

Status	Visibility	Fields	Trigger
completed	Public	agentId, status, prompt, tool results	Sync agent finishes
async_launched	Public	agentId, description, prompt, outputFile, canReadOutputFile	Async/background spawn
teammate_spawned	Internal (DCE)	teammate_id, agent_id, name, color, tmux identifiers, team_name	Teammate spawn
remote_launched	Internal (DCE)	taskId, sessionUrl, description, prompt, outputFile	Remote isolation (ant builds)
The canReadOutputFile boolean on async_launched results tells the parent whether it has Read or Bash tools to check progress — this prevents agents without file access from attempting to rd the output file.

Sources: AgentTool.tsx

Guard Rails and Constraints
Several invariant checks enforce architectural boundaries. Teammates cannot spawn other teammates — the team rosters flat, and nested teammates would confuse the lead's member tracking, enforced at AgentTool.tsx. In-process teammates cannot spawn background agents since their lifecycle is tied to the leader's process, enforced at AgentTool.tsx. Fork children cannot recursively fork, with both a querySource check (compaction-resistant) and a message-scan fallback at AgentTool.tsx. MCP server availability is validated before spawning agents with requiredMcpServers, with a 30-second polling loop for pending connections at AgentTool.tsx.

Sources: AgentTool.tsx, AgentTool.tsx

Background task detachment: Async agents are deliberately not linked to the parent's abort controller at AgentTool.tsx. Pressing ESC to cancel the main thread does not kill background agents — they must be explicitly terminated via the kill command otask management UI. This design prevents an impatient user from accidentally destroying long-running background work.

Prompt Engineering for Agent Delegation
The tool's prompt in prompt.ts provides extensive guidance to the LLM on when and how to use each spawn path. When the fork experiment is active, additional sections cover fork semantics — when to fork (research andmplementation work where intermediate output is disposable), directive-style prompts (since forks inherit context), and anti-patterns like peeking at output files mid-flight or racing to predict fork results. The prompt distinguishes between fork prompts (short directives) and typed-agent prompts (full briefings for agents starting with zero context), and explicitly warns against delegation patterns like "based on your findings, fix the bug" that push synthesis onto the sub-agent.


