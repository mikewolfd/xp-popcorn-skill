# Alternative Architecture Proposal

An alternate take on the popcorn-xp architecture — same goals, fewer moving parts. This is a proposal, not a plan. It documents what a leaner version of the system would look like and why, so the tradeoffs are visible before any code moves.

The core XP collaboration model is untouched: lenses, typed advice (OBJECTION/SMELL/STEER/FYI), append-only session files, protocol auto-loading, mandatory retros, and the shutdown lifecycle. The cuts are in the enforcement and observation layers.

## Motivation

Three audits (codebase accuracy, official docs correctness, agent definition validation) surfaced a pattern: most of the system's complexity lives in the hook layer, and most of that complexity exists to remind agents of things the protocol already instructs. The hooks that enforce hard invariants (OBJECTION gate, retro gate, shutdown lifecycle) are sound. The hooks that nudge soft behaviors (checkpoint reminders, unread advice reminders, context store awareness) add fragility — parallel execution conflicts, grep-based markdown parsing, platform-specific locking — for marginal value over what the protocol prompt already provides.

Key findings that motivate this proposal:

- **AA1 (shutdown deadlock)**: Three TeammateIdle hooks run in parallel. `remind-unread-advice.sh` (exit 2) can override `enforce-no-idle.sh` (`continue: false`), preventing shutdown. Removing the reminder hooks eliminates the conflict entirely.
- **AA10 (platform portability)**: Context store hooks use `lockf` (macOS-only). Removing them eliminates the only platform-specific dependency.
- **AA2 (agent naming)**: All 10 agents manually include the `popcorn-xp:` prefix that the plugin system auto-adds, relying on undocumented double-prefix handling.
- **SKILL.md size**: 547 lines loaded into the lead's context at every turn. Reference material (decomposition examples, spawn templates, retro format) is consulted once but paid for on every turn.

## Change 1: Cut hooks from 14 to 6

### Delete (8 scripts)

| Script | Current purpose | Why it can go |
|--------|----------------|---------------|
| `mark-dirty.sh` | Counts uncheckpointed edits, sets `.dirty`/`.edit-count` | Protocol already instructs "one edit = one checkpoint." Feeds `remind-checkpoint.sh` which is also being removed. |
| `remind-checkpoint.sh` | TeammateIdle: nags driver to checkpoint | Protocol instructs checkpointing. Navigator catches missed checkpoints via advice. Removing this eliminates the `.dirty`/`.edit-count` signal files. |
| `remind-unread-advice.sh` | TeammateIdle: nags about open advice | Protocol instructs "read ADVICE.md before starting work and before completing a task." Removing this eliminates the AA1 shutdown deadlock. |
| `context-store-check.sh` | PreToolUse Read: injects cache-hit metadata | Soft awareness only — doesn't block. Better solved by explicit file ownership in task descriptions. |
| `context-store-mark-dirty.sh` | PreToolUse Edit/Write: soft-lock warning | Informational only — doesn't block. Same file ownership alternative. |
| `context-store-update-read.sh` | PostToolUse Read: records reads in JSON | Feeds the context store that the other two hooks read. Without them, no consumers. |
| `context-store-log.sh` | Helper sourced by context store hooks | No consumers without the context store. |
| `notify-retro-written.sh` | PostToolUse Write: nudges agent to SendMessage lead after retro | Replace with a protocol instruction: "After writing your retro, SendMessage the lead to confirm." One line in the protocol skill. |

### Keep (6 scripts)

| Script | Event | Why it stays |
|--------|-------|-------------|
| `check-advice-on-complete.sh` | TaskCompleted | The core invariant. OBJECTIONs must block task completion. Agents will occasionally skip this; mechanical enforcement is necessary. |
| `check-objections.sh` | SubagentStop | Backup OBJECTION gate. Catches the edge case where a teammate stops without completing its task. |
| `check-rotation.sh` | TaskCompleted | Rotation warning. Non-blocking (exit 0 with additionalContext), but the lead needs this signal to enforce the mandatory-rotation rule. |
| `enforce-no-idle.sh` | TeammateIdle | Shutdown lifecycle enforcement. The four-phase logic (retro-pending > shutdown > retro-done > working) is mechanical and correct. With the other two TeammateIdle hooks gone, this becomes the sole handler — no parallel conflict possible. |
| `check-retro-before-delete.sh` | PreToolUse (TeamDelete) | Retro gate. Blocks TeamDelete until RETRO.md exists with real content. |
| `notify-retro-received.sh` | FileChanged (.retro-*.md) | Retro arrival notification for the lead. Part of the shutdown lifecycle. |

### Resulting hooks.json

```json
{
  "description": "Popcorn XP lifecycle hooks — advice enforcement, rotation, shutdown, and retro gating",
  "hooks": {
    "TaskCompleted": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/check-advice-on-complete.sh",
            "timeout": 10,
            "statusMessage": "Checking advice before task completion..."
          },
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/check-rotation.sh",
            "timeout": 10,
            "statusMessage": "Checking driver rotation..."
          }
        ]
      }
    ],
    "SubagentStop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/check-objections.sh",
            "timeout": 10
          }
        ]
      }
    ],
    "TeammateIdle": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/enforce-no-idle.sh",
            "timeout": 5
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "TeamDelete",
        "hooks": [
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/check-retro-before-delete.sh",
            "timeout": 10,
            "statusMessage": "Checking for retrospective..."
          }
        ]
      }
    ],
    "FileChanged": [
      {
        "matcher": "\\.retro-.*\\.md$",
        "hooks": [
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/notify-retro-received.sh",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

### What this eliminates

- Zero hooks fire on Read, Edit, or Write. The hot path is completely clean.
- No `.dirty` or `.edit-count` signal files.
- No `context-store.json` or `context-store.log`.
- No `lockf` dependency (macOS-only portability issue gone).
- No parallel TeammateIdle conflict (AA1 resolved structurally).

### Risk

Agents that ignore the protocol's checkpointing instructions won't be nagged. The navigator is the fallback — they should catch missed checkpoints via SMELL advice. If this proves insufficient in practice, a single combined TeammateIdle script could be added back that checks both checkpoint state and advice state, avoiding the parallel execution problem by consolidating into one handler.

---

## Change 2: Strip agent name prefix, fix invalid colors

### Agent names

The plugin system auto-namespaces agents as `<plugin-name>:<agent-name>`. All 10 agents manually include the `popcorn-xp:` prefix, which may produce `popcorn-xp:popcorn-xp:expert` at runtime (AA2). The system appears to handle this gracefully today, but it relies on undocumented behavior.

Change every agent's `name` field to the bare name:

| File | Before | After |
|------|--------|-------|
| `agents/expert.md` | `name: popcorn-xp:expert` | `name: expert` |
| `agents/craftsman.md` | `name: popcorn-xp:craftsman` | `name: craftsman` |
| `agents/scout.md` | `name: popcorn-xp:scout` | `name: scout` |
| `agents/tester.md` | `name: popcorn-xp:tester` | `name: tester` |
| `agents/qa.md` | `name: popcorn-xp:qa` | `name: qa` |
| `agents/service-designer.md` | `name: popcorn-xp:service-designer` | `name: service-designer` |
| `agents/visual-designer.md` | `name: popcorn-xp:visual-designer` | `name: visual-designer` |
| `agents/product-manager.md` | `name: popcorn-xp:product-manager` | `name: product-manager` |
| `agents/strategist.md` | `name: popcorn-xp:strategist` | `name: strategist` |
| `agents/code-reviewer.md` | `name: popcorn-xp:code-reviewer` | `name: code-reviewer` |

### Invalid colors

`magenta` is not in the documented valid set (`red`, `blue`, `green`, `yellow`, `purple`, `orange`, `pink`, `cyan`).

| File | Before | After |
|------|--------|-------|
| `agents/code-reviewer.md` | `color: magenta` | `color: purple` |
| `agents/visual-designer.md` | `color: magenta` | `color: pink` |

### Cascade

Update all references to `popcorn-xp:craftsman` etc. in:
- `skills/popcorn-xp/SKILL.md` role roster table
- `docs/architecture.md` agent tables
- `references/protocol.md` if any hardcoded agent names

### Risk

If the plugin system does NOT auto-prefix (contrary to the official docs), agents would lose their namespace and could collide with user-defined agents of the same name. Test by checking what `/agents` displays after the change. If the auto-prefix is confirmed, this is a clean win. If not, revert.

---

## Change 3: Extract SKILL.md reference material

### Problem

SKILL.md is 547 lines. All of it loads into the lead's context at startup and persists across every turn. Roughly 60% of the content is reference material consulted once during a specific step (decomposition examples during Step 3, spawn templates during Step 4, retro format during Step 6).

### Proposed structure

SKILL.md shrinks to ~180 lines. Reference material moves to files in `skills/popcorn-xp/` that the lead reads on demand.

**New files:**

| File | Extracted from | ~Lines | Read when |
|------|---------------|--------|-----------|
| `skills/popcorn-xp/task-decomposition.md` | SKILL.md lines 223-313 (decomposition checklist, examples, parallel patterns, QA guidance) | ~90 | Step 3: before creating tasks |
| `skills/popcorn-xp/spawn-templates.md` | SKILL.md lines 60-103, 332-387 (native agent mapping, spawn examples) | ~100 | Step 4: before spawning teammates |
| `skills/popcorn-xp/retro-format.md` | SKILL.md lines 451-493 (retro file template) | ~45 | Step 6: before writing RETRO.md |

**Revised SKILL.md outline** (~180 lines):

```
## Prior session context              (dynamic injection, unchanged)
# Popcorn XP                          (trigger conditions, 1-paragraph summary)
## Role Roster                         (lens table only, no mapping reference)
## 1. Understand the Task              (~15 lines)
## 2. Create the Team                  (~40 lines — model choice, agent scan, setup)
## 3. Create Tasks                     (~15 lines — principles, then: "Read task-decomposition.md")
## 4. Spawn Teammates                  (~15 lines — principles, then: "Read spawn-templates.md")
## 5. Monitor                          (~40 lines — operational, unchanged)
## 6. Verify and Close                 (~30 lines — shutdown sequence + "Read retro-format.md")
## Advice System                       (~15 lines — summary table)
## Session Files                       (~10 lines — file list)
## Quality Bar                         (~10 lines)
```

### Session script extraction

The `session` helper script is currently a 20-line heredoc embedded in SKILL.md Step 2. Move it to `bin/session` as a standalone file. Step 2 becomes:

```bash
cp "${CLAUDE_PLUGIN_ROOT}/bin/session" ".popcorn-xp/$TEAM/session"
chmod +x ".popcorn-xp/$TEAM/session"
```

This makes the session script independently testable and saves 20 lines from the lead's persistent context.

### Risk

The lead must remember to read the reference files at the right step. If it skips the read, it loses the decomposition checklist or spawn examples. Mitigation: each step's instruction explicitly says "Read `task-decomposition.md` before proceeding." The lead's protocol compliance is generally high — this is an orchestration instruction, not a soft nudge.

---

## Change 4: Remove redundant `references/protocol.md` body references

### Problem

Multiple agent bodies say "you follow the protocol in `references/protocol.md`" (e.g., `expert.md:43`, `craftsman.md:43`). The protocol is already injected via `skills: [popcorn-xp-protocol]`. This can cause agents to waste a tool call reading a 623-line file whose content is already in context.

### Change

In each agent file that references `references/protocol.md`, replace:

```markdown
# Before
When participating in a popcorn-xp session, you follow the protocol in `references/protocol.md`.

# After
When participating in a popcorn-xp session, you follow the protocol (auto-loaded at startup).
```

### Risk

None. The protocol content is already in context via the `skills` field. This only removes a misleading file path reference.

---

## Change 5: Sync lens text to one source of truth

### Problem

Lens descriptions exist in three places and have drifted (AA6):

| Agent | `agents/*.md` (runtime canonical) | `SKILL.md` (lead reference) | `docs/architecture.md` |
|-------|----------------------------------|----------------------------|------------------------|
| service-designer | "Does the interface serve the experience — from API contract to user interaction?" | "Does the interface serve the experience — API to UI?" | "Does the interface serve the experience?" |
| product-manager | "What problem are we solving, and is this the right way to solve it?" | "What problem are we solving, and is this the right way?" | "What problem are we solving?" |
| tester | "How will we prove this works?" | "How will we prove this?" | "How will we prove this works?" |

### Change

Agent files are the canonical source (they're what the runtime loads). Update SKILL.md and `docs/architecture.md` to match the agent files exactly.

### Risk

None.

---

## Change 6: Document the sole-TeammateIdle-hook invariant

With Change 1, `enforce-no-idle.sh` becomes the only TeammateIdle hook. This is what eliminates the AA1 deadlock. If someone adds another TeammateIdle hook in the future, the deadlock returns.

### Change

Add a comment to `enforce-no-idle.sh`:

```bash
# IMPORTANT: This must be the ONLY TeammateIdle hook in hooks.json.
# Multiple TeammateIdle hooks run in parallel per the official docs.
# Exit 2 from another hook can override the {"continue": false} shutdown
# signal, preventing agents from stopping. If you need additional
# TeammateIdle behavior, add it to this script's phase logic — do not
# register a separate hook.
```

Also add the same note to `hooks.json` as a comment in the description field:

```json
"description": "Popcorn XP lifecycle hooks. IMPORTANT: TeammateIdle must have exactly one hook (enforce-no-idle.sh) to avoid parallel execution conflicts with shutdown."
```

### Risk

None. This is documentation, not a behavioral change.

---

## Summary

| | Before | After |
|--|--------|-------|
| Hook scripts | 14 | 6 |
| Hook events with handlers | 6 | 4 |
| Hooks on Read/Edit/Write | 5 | 0 |
| Signal files | 6 | 4 |
| SKILL.md lines | 547 | ~180 |
| Reference files | 1 | 4 |
| Agent name format | `popcorn-xp:expert` (manual) | `expert` (auto-prefixed) |
| Context store | 3 hooks + helper + JSON + log | Gone |
| Platform-specific deps | `lockf` (macOS) | None |
| Known deadlock vectors | 1 (AA1) | 0 |

### What's preserved unchanged

- The advice system (OBJECTION/SMELL/STEER/FYI lifecycle)
- The protocol skill (auto-loaded into every agent)
- The `session` script interface (log, advice, resolve, task, handoff, retro, shutdown)
- ADVICE.md, LOG.md, RETRO.md format and semantics
- The shutdown lifecycle phases (retro-pending > shutdown > retro-done > working)
- The retro gate on TeamDelete
- The OBJECTION gate on TaskCompleted and SubagentStop
- The rotation warning on TaskCompleted
- The FileChanged retro notification
- The lens abstraction and all agent definitions (content unchanged, only frontmatter adjusted)

### Open questions

1. **Does the plugin system actually auto-prefix agent names?** Change 2 depends on this. Needs a runtime test before committing.
2. **Does `TeamDelete` fire as a PreToolUse matcher?** AA3 is unresolved. If not, `check-retro-before-delete.sh` silently never fires and the retro gate needs a different enforcement point.
3. **Is the navigator sufficient as a checkpoint reminder?** Change 1 bets that protocol compliance + navigator advice replaces mechanical nagging. If agents consistently skip checkpoints without the hook, a consolidated single-script fallback can be added back to `enforce-no-idle.sh`'s phase 4 (working) path.
4. **Does `enforce-no-idle.sh` receive `teammate_name` in hook input for all teammate types?** AA4 is unresolved. If not, the retro-pending phase can't check for agent-specific retro files.
