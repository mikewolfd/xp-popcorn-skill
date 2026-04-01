# Popcorn XP Retro

## Session: 2026-04-01 — Form workflow framework using SpiffWorkflow

### Team
- Driver(s): craftsman drove all 6 tasks
- Navigator(s): expert navigated all 6 tasks
- Advisor(s): scout (orientation only, idle after round 0)

### What Worked
- Scout orientation before implementation saved the team from multiple dead ends (serializer API, missing `get_ready_user_tasks()`, BPMN-only imports). Probe script with 8 validated tests gave craftsman a reference implementation.
- Expert proactive navigation — filed advice before craftsman wrote code, not after. Two OBJECTIONs caught real bugs pre-implementation.
- Tasks were scoped tightly enough that craftsman completed all 6 without any needing to be split or re-scoped.
- SML-3-1 (checkbox absent vs false edge case) was raised, fixed, and tested in a natural final pass. The advice system worked as designed.

### What Didn't Work
- Craftsman drove all 6 tasks. No rotation happened despite the protocol requiring it. Expert should have driven tasks #5 or #6 after navigating the implementation.
- Scout went idle after orientation and was never reassigned. Could have driven test review, demo validation, or final verification.
- Shutdown was messy — craftsman cycled idle 4+ times before processing the shutdown request. Multiple round-trips wasted.
- Lead skipped the retro step entirely and had to be reminded by the user. The retro was in the skill but wasn't treated as mandatory.

### Advice System
- OBJECTIONs raised: 2 (OBJ-2-1: get_ready_user_tasks missing, OBJ-2-2: serializer drops form_schema)
- OBJECTIONs fixed: 2
- OBJECTIONs rejected: 0
- SMELLs/STEERs/FYIs: 3 STEERs, 1 SMELL, 1 FYI
- Assessment: Good balance. OBJECTIONs were used for real bugs only. SML-3-1 was appropriately classified as a smell rather than an objection — it was a subtle edge case, not a showstopper. Expert held opinions loosely.

### Rotation
- No rotation occurred. This is the biggest process failure of the session. Craftsman drove every task, expert navigated every task. The expert had full context from watching all implementation and should have driven the test or demo tasks. The "navigator becomes driver" pattern was never applied.

### Process Observations
- The lead relayed scout findings to craftsman and expert via SendMessage — this worked well but could have been unnecessary if scout had sent directly (they may have, but the relay ensured it).
- Teammate idle notifications don't clearly distinguish "idle and waiting for work" from "idle and ignoring shutdown." Need a cleaner signal.
- The retro step in the skill was positioned correctly (before user summary) but the lead skipped it anyway. Making it harder to skip by reordering the close-out sequence.

### Recommendations
- Enforce at least one driver rotation per session. Added to skill.
- Plan a second assignment for orientation agents. Added to skill.
- Add shutdown escalation protocol (3 attempts then move on). Added to skill.
- Retro is now mandatory and sequenced before the user-facing summary. Updated in skill.
- Next session: start with scout driving orientation, then rotate craftsman in as driver with expert navigating, then rotate expert to driver for verification/tests.
