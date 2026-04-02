Deep Dive
Coordinator Mode
Report Issue
11 min
Level: Advanced
Coordinator Mode transforms Claude Code from a single-agent tool executor into a multi-agent orchestrator. In this mode, the main session relinquishes direct filesystem and shell access, retaining only worker lifecycle management tools, while delegating all concrete work — research, implementation, verification — to asynchronously spawned worker agents. This architectural inversion is the foundation of the platform's horizontal scaling strategy for complex software engineering tasks.

Activation and Feature Gating
Coordinator Mode is guarded by a two-layer gate: a compile-time Bun bundle feature flag and a runtime environment variable. The isCoordinatorMode() function in coordinatorMode.ts checks feature('COORDINATOR_MODE') first — if the flag is absent from the bundle, the function short-circuits to false regardless of environment state. When the flag is present, it reads process.env.CLAUDE_CODE_COORDINATOR_MODE via isEnvTruthy(). To-tier design prevents the mode from being accidentally activated in builds that don't include the multi-agent tooling, and avoids shipping coordinator-aware code paths in standard distributions.

Session resumption introduces a subtlety: if a user starts a session in coordinator mode, closes it, then reopens it without the env var set, the resumed session would be in a mismatched state. The matchSessionMode() function at coordinatorMode.ts#L49-L78 handles this by comparing the stored session mode against the current runtime mode. On mismatch, it flips the environment variable in-place (since isCoordinatorMode() reads process.env live with no caching) and logs an analytics event tengu_coordinator_mode_switched, returning a human-readable warning string that the REPL can display. This ensures coordinator sessions survive restart boundaries.

Tool Restriction Architecture
The most consequential design decision in Coordinator Mode is the asymmetric tool partitioning between the coordinator and its workers. This is not a simple role-based access control — it is a structural inversion of the normal Claude Code tool graph.

Coordinator Tool Set
When coordinator mode is active, the main session's tool pool is reduced to COORDINATOR_MODE_ALLOWED_TOOLS defined in tools.ts#L107-L112:

Tool	Constant	Purpose
Agent	AGENT_TOOL_NAME	Spawn new worker agents
SendMessage	SEND_MESSAGE_TOOL_NAME	Continue an existing worker with follow-up instructions
TaskStop	TASK_STOP_TOOL_NAME	Stop a running worker mid-flight
StructuredOutput	SYNTHETIC_OUTPUT_TOOL_NAME	Produce structured JSON output to the user
The coordinator has no Bash, FileRead, FileEdit, Grep, Glob, WebSearch, or any other tool that touches the filesystem or external services. It is purely a management and synthesis layer.

Worker Tool Set
Workers receive the complement. The getCoordinatorUserContext() function at coordinatorMode.ts#L80-L109 constructs a context string listing available worker tools. The tool set is derived from ASYNC_AGENT_ALLOWED_TOOLS (defined at too.ts#L55-L65) with four internal tools explicitly subtracted:

const INTERNAL_WORKER_TOOLS = new Set([
  TEAM_CREATE_TOOL_NAME,   // 'TeamCreate'
  TEAM_DELETE_TOOL_NAME,   // 'TeamDelete'
  SEND_MESSAGE_TOOL_NAME,  // 'SendMessage'
  SYNTHETIC_OUTPUT_TOOL_NAME, // 'StructuredOutput'
])
This subtraction at coordinatorMode.ts#L29-L34 prevents workers from spawning their own sub-teams, sending messages to other workers (only the coordinator routes inter-worker communication), or producing structured output — these are coordinator-exclusive capabilities. The remaining worker tools include FileRead, FileEdit, FileWrite, Bash, Grep, Glob, WebSearch, WebFetch, TodoWrite, and the Skill tool (for invoking project skills like /commit or /verify).

In "simple" mode (when CLAUDE_CODE_SIMPLE is set), the worker tool set degrades to just Bash, FileRead, and FileEdit, as seen at coordinatorMode.ts#L88-L91.

Scratchpad Integration
When the tengu_scratch feature gate is enabled, getCoordinatorUserContext() appends scratchd directory information at coordinatorMode.ts#L104-L106. The scratchpad provides a shared filesystem location where workers can read and write without permission prompts, enabling durable cross-worker knowledge transfer through structured files. The scratchpad path is injected via the scratchpadDir parameter to avoid a circular dependency with the filesystem permission module.

Coordinator System Prompt
The getCoordinatorSystemPrompt() function at coordinatorMode.ts#L111-L370 generates the full behavioral specification for the coordinator. This is not a generic orchestration prompt — it is a meticulously engineered 260-line directive that encodes the entire coordinator protocol.

Role Definition
The coordinator is instructed to act as a pure orchestrator: it helps the user achieve goals by directing workers to research, implement, and verify code changes, then synthesizes results. Critically, it is told to answer questions directly when possible without delegating — coordinator mode does not mean "alwayawn workers for everything." Workers are tools to be used when they provide genuine value.

Task Notification Protocol
Worker results arrive as user-role messages containing <task-notification> XML, as documented at coordinatorMode.ts#L144-L160. The XML structure is:

<task-notification>
  <task-id>{agentId}</task-id>
  <status>completed|failed|killed</status>
  <summary>{human-readable status summary}</summary>
  <result>{agent's final text response}</result>
  <usage>
    <total_tokens>N</total_tokens>
    <tool_uses>N</tool_uses>
    <duration_ms>N</duration_ms>
  </usage>
</task-notification>
The <result> and <usage> sections are optional. The coordinator must distinguish these notifications from actual user messages by the <task-notification> opening tag. The task-id value doubles as the agent ID for SendMessage continuation.

Phased Task Workflow
The system prompt defines a four-phase decomposition pattern at coordinatorMode.ts#L200-L209:

Phase	Executor	Purpose
Research	Workers (parallel)	Investigate codebase, find files, understand problem
Synthesis	Coordinator	Read findings, understand the problem, craft implementation specs
Implementation	Workers	Make targeted changes per spec, commit
Verification	Workers	Test changes work
The synthesis phase is explicitly assigned to the coordinator, not delegated. This is the core architectural insight: the coordinator must understand findings before directing follow-up work. The prompt forbids lazy delegation patterns like "based on your findings" — every synthesized prompt must include specific file paths, line numbers, and exact instructions.

Concurrency Model
The prompt emphazes parallelism as the coordinator's "superpower" at coordinatorMode.ts#L211-L218. Read-only research tasks can run freely in parallel. Write-heavy implementation tasks should be serialized per set of files to avoid conflicts. Verification can sometimes run alongside implementation on different file areas.

Continue vs. Spawn Decision Matrix
One of the most nuanced aspects of coordinator behavior is choosing between continuing an existing worker via SendMessage and spawning a fresh worker via Agent. The system prompt provides a detailed decision matrix at coordinatorMode.ts#L282-L293:

Situation	Mechanism	Rationale
Research explored exactly the files that need editing	Continue	Worker already has relevant files in context
Research was broad but implementation is narrow	Spawn fresh	Avoid dragging exploration noise
Correcting a failure or extending recent work	Continue	Worker has error context
Verifying code a different worker wrote	Spawn fresh	Verifier should see code with fresh eyes
First attempt used wrong approach entirely	Spawn fresh	Wrong-approach context pollutes retry
Completely unrelated task	Spawn fresh	No useful context to reuse
Worker Lifecycle Integration
Spawning via AgentTool
Workers are spawned through the AgentTool defined in AgentTool.tsx. The coordinator calls Agent with subagent_type: "worker" and a self-contained prompt. The input schema supports description, prompt, subagent_type, model, run_in_background, and multi-agent parameters like name, team_name, and mode. The isCoordinatorMode() check is imported at AgentTool.tsx#L9, enabling the AgentTool to adapt its behavior when the coordinator is the caller.

The runAgent() function in runAgent.ts executes the worker's main loop. It accepts an availableTools parameter — a precomputed tool pool assembled by the caller with the rker's own permission mode, independent of the parent's tool restrictions. The allowedTools parameter replaces all inherited allow rules so the coordinator's tool approvals don't leak through to workers.

Continuation via SendMessageTool
The SendMessageTool at SendMessageTool.ts handles follow-up messages to running workers. It supports targeted messages (via to parameter with agent name), broadcasts (to: "*"), and structured message types including shutdown requests/responses and plan approvals/rejections. The tool locates teammate tasks by agent ID through findTeammateTaskByAgentId() and queues messages for both in-process teammates and local agent tasks.

Stopping via TaskStopTool
When a worker is sent in the wrong direction or the user changes requirements, the coordinator uses TaskStopTool to terminate it mid-flight, passing the task_id from the AgentTool's launch result.

In-Process Teammate Execution
Workers run as in-process teammates managed by InProcessTeammateTask (InProcessTeammateTask.tsx). The InProcessRunnerConfig type at inProcessRunner.ts#L471-L503 defines the full configuration including identity, task ID, prompt, agent definition, and permission context. The runInProcessTeammate() function at inProcessRunner.ts#L883 executes the teammate's main loop with auto-compaction, permission bridging, and idle notification handling.

Teammate identity is captured in the TeammateIdentity type at types.ts#L13-L19:

type TeammateIdentity = {
  agentId: string      // e.g., "researcher@my-team"
  agentName: string    // e.g., "researcher"
  teamName: string
  color?: string
  planModeRequired: boolean
  parentSessionId: string  // Leader's session ID
}
This identity is stored as plain data in AppState (not a reference to AsyncLocalStorage's TeammateContext) for persistence across renders.

Message Capping
In-process teammate message arrays are capped at TEAMMATE_MESSAGES_UI_CAP = 50 entries by the appendCappedMessage() utility at types.ts#L101-L119. When the cap is reached, the oldest messages are dropped. This prevents unbounded memory growth in long-running coordinator sessions with many active workers.

Architecture Overview





























Task State Integration
In-process teammate tasks are registered in the global AppState as InProcessTeammateTaskState objects, which extend TaskStateBase with teammate-specific fields. The TaskState union type at tasks/types.ts#L12-L19 includes InProcessTeammateTaskState alongside other task variants (local agent, remote agent, shell, workflow, etc.). In-process teammates participate in the same background task indicator system as other task types, unified by the BackgroundTaskState union.

The getRunningTeammatesSorted() function at InProcessTeammateTask.tsx#L123 returns running in-process teammates sorted alphabetically by agentName. This sort order is a shared contract between the TeammateSpinnerTree display, the PromptInput footer selector, and useBackgroundTaskNavigation — the selectedIPAgentIndex maps into this array, so all three consumers must agree on ordering.

The coordinator mode tool partitioning is not just an accescontrol list — it is a communication topology constraint. Workers cannot message each other directly; all inter-worker communication must be routed through the coordinator via SendMessa. This star topology prevents coordination deadlocks and ensures the coordinator maintains a complete picture of all worker states.

When resuming a coordinator session, matchSessionMode() flips process.env.CLAUDE_CODE_COORDINATOR_MODE in-place because isCoordinatorMode() reads the environment variable live with no caching. This is a deliberate design choice that trades purity for session continuity — any code path calling isCoordinatorMode() after the flip will see the updated value immediately.
elationship to Swarm Teams
Coordinator Mode and the Swarm Team system (driven by TeamCreateTool/TeamDeleteTool) are related but distinct coordination models. Coordinator Mode uses the Agent tool with subagent_type: "worker" to spawn anonymous, task-scoped workers that report back via <task-notification> XML. Swarm Teams, by contrast, create named, addressable teammates with persistent identities, colors, and mailbox-based communication, managed through SendMessage with structured routing.

The key distinction is that TeamCreate and TeamDelete are in INTERNAL_WORKER_TOOLS — workers cannot create or dissolve teams. Team lifecycle management is a coordinator (or swarm leader) exclusiveapability, preventing workers from spawning uncontrolled sub-teams.
