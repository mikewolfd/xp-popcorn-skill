Team Agent Management
Report Issue
15 min
Level: Advanced
Team Agent Management is the subsystem that governs how Claude Code orchestrates multiple LLM-powered agents into cooperative swarms. It encompasses team lifecycle (creation, membership, teardown), teammate execution across heterogeneous backends, file-based inter-agent messaging, permission delegation, and session-resilient state management. This system is the operational backbone of the swarm/coordination paradigm documented in Coordinator Mode and materialized through the built-in agent types described in Built-In Agent Types.

Architectural Overview
The team agent system is decomposed into four horizontal layers: Lifecycle, Execution, Messaging, and Delegation. Each layer has clear boundaries but shares a common persistence substrate rooted in the filesystem at ~/.claude/teams/.





















The coordinator (team lead) invokes TeamCreateTool to establish a team, then spawnMultiAgent to bring teammates to life across one of three execution backends. Communication flows through the mailbox system, while permission decisions follow a leader-authorizes-worker pattern via the permission sync subsystem.

Team Lifecycle
Team Creation
TeamCreateTool is the sole mechanism for establishing a swarm. It accepts a team_name (required), description (optional), and agent_type (optional role label for the lead). The tool enforces a single-team-per-leader constraint — if AppState.teamContext.teamName is already populated, it throws an error instructing the coordinator to call TeamDelete first TeamCreateTool.ts#L132-L139.

On successful creation, the tool performs five sequential operations:

Name resolution — If the requested name already exists on disk, generateUniqueTeamName falls back to generateWordSlug() to produce a collision-free identifier TeamCreateTool.ts#L64-L72.
Agent ID generation — The lead receives a deterministic ID of the form team-lead@{teamName}, produced by formatAgentId(TEAM_LEAD_NAME, finalTeamName) TeamCreateTool.ts#L146.
ile persistence — A TeamFile object is written to ~/.claude/teams/{sanitizedName}/config.json via writeTeamFileAsync TeamCreateTool.ts#L157-L177.
Task list initialization — A task directory is created at the sanitized team name, and the leader's task list ID is bound via setLeaderTeamName so that both leader and out-of-process teammates resolve to the same task namespace TeamCreateTool.ts#L183-L191.
AppState mutation — The teamContext field is populated with teamName, teamFilePath, leadAgentId, and an initial teammates map containing the lead itself TeamCreateTool.ts#L194-L212.
Critically, the lead's agent ID is not set in process.env. This deliberate omission ensures isTeammate() returns false for the lead, preserving correct inbox routing semantics TeamCreateTool.ts#L224-L228.

Team File Structure
The TeamFile is the single source of truth for team membership and state, persisted as JSON on disk:

Field	Type	Purpose
name	string	Sanitized team identifier
description	string?	Optional human-readable pucreatedAt	number	Epoch timestamp of creation
leadAgentId	string	Deterministic lead ID (team-lead@{name})
leadSessionId	string?	Actual session UUID for discovery
hiddenPaneIds	string[]?	Pane IDs hidden from swarm view UI
teamAllowedPaths	TeamAllowedPath[]?	Paths all teammates can edit without permission prompts
members	Member[]	Array of joined agents with pane IDs, models, modes, subscriptions
Each member record carries agentId, name, agentType, model, tmuxPaneId, cwd, subscriptions, permission mode, and isActive status teamHelpers.ts#L64-L91.

Sources: teamHelpers.ts

Team Deletion
TeamDeleteTool performs the inverse operation with no input parameters. It reads the current team name from AppState, then invokes cleanupTeamDirectories to remove the team directory, task directories, and any git worktrees created for teammates TeamDeleteTool.ts#L11-L14. It also clears teammate color assignments, unregisters the team from session cleanup tracking, and nullifies the leader's team name binding TeamDeleteTool.ts#L15-L16.

Session-Resilient Cleanup
Teams registered via registerTeamForSessionCleanup are tracked in a session-scoped set. On graceful shutdown, cleanupSessionTeams iterates all registered teams, kills orphaned panes, and removes their directories teamHelpers.ts#L560-L591. If a team was explicitly deleted via TeamDeleteTool, it is unregistered beforehand to avoid double-cleanup teamHelpers.ts#L568-L570.

Session Resume and Reconnection
When a session is resumed, computeInitialTeamContext checks for CLAUDE_CODE_TEAM_NAME environment variables (set on spawned teammates) or reads the team file from disk to reconstruct the teamContext in AppState reconnection.ts#L23-L73. This allows a coordinator to rejoin an existing swarm after process restart without re-creating the team.

Sources: TeamCreateTool.ts, TeamDeleteTool.ts, teamHelpers.ts, reconnection.ts

Teammate Execution Backends
The system supports three distinct execution strategies, selected automatically at spawn time through the backend registry.

Backend Detection and Selection
The detectAndGetBackend function in the backend registry evaluates the runtime environment in this priority order registry.ts#L136-L254:

Explicit session override — getTeammateModeFromSnapshot reads the mode captured at startup, honoring --teammate-mode CLI flags.
Non-interactive sessions — Force in-process mode when no terminal is available.
iTerm2 detection — Checks TERM_PROGRAM === "iTerm.app" and isIt2CliAvailable().
tmux detection — Checks isInsideTmux() and isTmuxAvailable().
Fallback — If no pane backend is available, marks an in-process fallback flag so subsequent spawns short-circuit directly to in-process mode registry.ts#L322-L327.
Backend	Type	Visibility	Use Case
tmux	Pane-based	Native split panes inside/outside tmux	Default on Linux; server environments
iTerm2	Pane-based	Native iTerm2 split panes	macOS with iTerm2 + it2 CLI
in-process	AsyncLocalStorage	Background task pill only	Headless, CI, fallback
Sources: backends/types.ts, backends/registry.ts

The PaneBerface
Pane-based backends implement a common PaneBackend interface that abstracts terminal pane operations types.ts#L39-L168:

type PaneBackend = {
  readonly type: BackendType
  readonly displayName: string
  readonly supportsHideShow: boolean
  createPane(config: CreatePaneConfig): Promise<CreatePaneResult>
  sendText(paneId: PaneId, text: string): Promise<void>
  killPane(paneId: PaneId): Promise<boolean>
  getPaneId(sessionName: string, windowName: string, agentName: string): Promise<string | null>
  isActive(paneId: PaneId): Promise<boolean>
  capturePane(paneId: PaneId, maxLines?: number): Promise<string>
  // ... additional methods
}
The TeammateExecutor interface wraps backends into a spawn-oriented API used by the upper layers types.ts#L279-L304.

Sources: backends/types.ts, backends/types.ts

Teammate Spawning Flow
spawnTeammate in spawnMultiAgent.ts is the main entry point, invoked by both TeammateTool and AgentTool spawnMultiAgent.ts#L1088-L1094. It delegates to handleSpawn, which routes to one of three handlers:

















The split-pane handler (handleSpawnSplitPane) creates a shared tmux window layout with the leader on the left and teammates tiled on the right — or, when not inside tmux, creates a dedicated claude-swarm session with all panes tiled spawnMultiAgent.ts#L305-L539. The legacy separate-window handler creates each teammate in its own tmux window spawnMultiAgent.ts#L545-L754.

Every spawn ph performs teammate name deduplication via generateUniqueTeamName, which appends numeric suffixes when collisions occur (e.g., tester-2, tester-3) spawnMultiAgent.ts#L267-L298.

In-Process Teammates
In-process teammates run inside the same Node.js process as the coordinator, using AsyncLocalStorage for context isolation spawnMultiAgent.ts#L840-L1032. They are tracked as InProcessTeammateTask instances in AppState, providing message history, shutdown hooks, and idle detection InProcessTeammateTask.tsx#L24-L125. Helper functions like findTeammateTaskByAgentId and getRunningTeammatesSorted provide centralized task lookup — the latter enforces alphabetical sort order shared across the teammate spinner tree, prompt input footer selector, and backgund task navigation InProcessTeammateTask.tsx#L86-L125.

In-process teammates are the only execution mode available in headless/print environments and serve as the automatic fallback when neither tmux nor iTerm2 tooling is detected. Once markInProcessFallback() is called, the flag persists for the process lifetime — the environment won't change mid-session.

Sources: spawnMultiAgent.ts, InProcessTeammateTask.tsx, spawnInProcess.ts

Int-Agent Messaging
The mailbox system is the communication backbone for all agent-to-agent interactions within a swarm. It uses file-based JSON message queues stored at ~/.claude/teams/{teamName}/inboxes/{agentName}.json.

Mailbox Architecture
Each agent owns an inbox file. Messages are written by callers and read by the inbox owner via file-locking to prevent race conditions teammateMailbox.ts#L34-L42. The core TeammateMessage type carries sender identity, text content, timestamp, read status, an optional color for UI differentiation, and a summary field used as a preview teammateMailbox.ts#L43-L50.

Key operations:

Function	Purpose
writeToMailbox(recipient, message)	Append a message to the recipient's inbox with file locking
readMailbox(agentName)	Read all messages from an agent's inbox
readUnreadMessages(agentName)	Read only unread messages
markMessagesAsRead(agentName)	Mark all messages as read atomically
formatTeammateMessages(messages)	Convert messages to XML for display in agent context
Sources: teammateMailbox.ts

SendMessageTool
The SendMessageTool is the coordinator's primary interface for directing teammates. It supports multiple addressing modes and structured protocol messages SendMessageTool.ts#L46-L131:

Direct message — to: "teammate-name" routes a message to a specific teammate's inbox.
Broadcast — to: "*" fans a message to all teammates simultusly SendMessageTool.ts#L191-L266.
Bridge peer — to: "bridge:<session-id>" routes to a Remote Control peer when UDS_INBOX is enabled SendMessageTool.ts#L72-L74.
UDS peer — to: "uds:<socket-path>" routes to a local Unix Domain Socket peer.
The tool also handles structured message routing for shutdown requests, shutdown approvals/rejections, and plan approval/rejection floendMessageTool.ts#L268-L519.

Structured Protocol Messages
The mailbox system defines a discriminated union of protocol message types, each with its own schema, creator function, and type guard teammateMailbox.ts#L394-L1072:

Protocol Message	Direction	Purpose
shutdown_request	Leader → Teammate	Request a teammate to terminate
shutdown_approved / shutdown_rejected	Teammate → Leader	Response to shutdown request
idle_notification	Teammate → Leader	Signal availability, interruption, or fapermission_request / permission_response	Worker ↔ Leader	Tool-use permission delegation
sandbox_permission_request / response	Worker ↔ Leader	Network host access approval for sandboxed workers
plan_approval_request / response	Teammate → Leader	Plan review workflow
task_assignment	Leader → Teammate	Task delnotification
team_permission_update	Leader → All	Broadcast permission rule updates
mode_set_request	Leader → Teammate	Change teammate permission mode
All protocol messages are serialize JSON within the mailbox's text field and detected via dedicated type guard functions (e.g., isShutdownRequest, isIdleNotification, isPermissionRequest). The isStructuredProtocolMessage predicate distinguishes protocol traffic from free-text messages teammateMailbox.ts#L1073-L1096.

Sources: SendMessageTool.ts, teammateMailbox.ts

Teammate Identity and Context
Dual Context Resolution
Each teammate's identity is resolved through a two-tier priority chain implemented in teammate.ts:

AsyncLocalStorage (in-process teammates) — TeammateContext is set via runWithTmmateContext when the teammate is spawned and propagated through AsyncLocalStorage.getStore().
Dynamic team context (tmux/iTerm2 teammates) — setDynamicTeamContext is called when a teammate joins a team at runtime, setting module-level state.
Functio like getAgentId(), getAgentName(), getTeamName(), isTeammate(), and getTeammateColor() all follow this priority chain teammate.ts#L83-L139. The isTeamLead function checks whether the current agent's ID matches the leadAgentId from the team file teammate.ts#L171-L198.

The lead's identity is intentionally not stored in process.env — only in AppState.teamContext. This ensus isTeammate() returns false for the lead, which is critical for correct inbox routing: the lead reads from the team-lead inbox, while teammates read from their own named inboxes. Mixing these up breaks the entire message flow.

Sources: teammate.ts

Permission Delegation
Leader-Worker Permission Model
When a teammate (worker) encounters a tool use that requires permission, it delegates the decision to the team lead via the permission sync system in permissionSync.ts.

The flow follows a request-response pattern through the mailbox:

Requests are written to ~/.claude/teams/{teamName}/permissions/pending/ with file locking and include the worker's ID, tool name, tool use ID, input, and permission suggestions permissionSync.ts#L215-L250. The leader reads pending requests via readPendingPermissions, resolves them with resolvePermission (moving from pending/ to resolved/), and sends a response message through the mailbox permissionSync.ts#L360-L451. Workers poll via pollForResponse which reads the resolved file and converts it into a simpler PermissionResponse format permissionSync.ts#L544-L565.

Stale resolved files older than one hour are cleaned up by cleanupOldResolutions permissionSync.ts#L452-L518.

Team-Wide Permission Updates
The lead can broadcast permission updates to all teammates via TeamPermissionUpdateMessage, which carries an addRules directive with tool names and allow/deny/ask behaviors teammateMailbox.ts#L983-L1001. Additionally, teamAllowedPaths in the team file stores paths that all teammates can edit without asking — these areanaged through TeamAllowedPath records that track which agent added the rule and when teamHelpers.ts#L57-L62.

Sources: permissionSync.ts, teamHelpers.ts

Coordinator Integration
Tool Restriction
In coordinator mode, the INTERNAL_WORKER_TOOLS set — containing TeamCreate, TeamDelete, SendMessage, and SyntheticOutput — is explicitly excluded from the worker tool list. This prevents workers from creating nested teams or sending arbitrarter-agent messages, keeping the coordination hierarchy flat and leader-controlled coordinatorMode.ts#L29-L34.

Coordinator System Prompt
The getCoordinatorSystemPrompt function generates a comprehensive instruction set that directs the LLM to act as an orchestration layer: spawning workers for research/implementation/verification, synthesizing findings into specific prompts, managing concurrency (parallel reads, serial writes), and handling failures by continuing existing workers via SendMessage rather than spawning replacements coordinatorMode.ts#L111-L370. The prompt mandates that every worker prompt be self-contained and synthesized — never delegated as vague "based on your findings" instructions coordinatorMode.ts#L252-L270.

Session Me Matching
When a session is resumed, matchSessionMode detects if the current CLAUDE_CODE_COORDINATOR_MODE environment variable disagrees with the stored session mode. If mismatched, it flips the variable and returns a warning, ensuring coordinator behavior is consistent across session boundaries coordinatorMode.ts#L43-L78.

Sources: coordinatorMode.ts

Telemetry and Observability
Team creation events are logged via logEvent('tengu_team_created', ...) with metadata including team name, teammate count, lead agent type, and the resolved teammate execution mode TeamCreateTool.ts#L214-L222. The logForDebugging utility is used throughout the spawning pipeline and mailbox system for development-time traceability.

Next Steps
Coordinator Mode — How coordinator mode transforms the LLM's system prompt and tool access for orchestration workflows.
Built-In Agent Types — The predefined agent roles (worker, teammate) and their configurations.
Agent Tool and Sub-Agent Spawning — The AgentTool that s coordinator-mode worker spawning and standalone sub-agent delegation.
Permission Model Overview — The broader permission system within which swarm permission delegation operates.
Coorditor Mode

