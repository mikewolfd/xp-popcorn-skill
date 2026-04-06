# Agent Pair Programming Protocol 1.0

**W3C-Style Working Draft**, 6 April 2026

**Latest published version:**
: <https://github.com/mikewolfd/xp-popcorn-skill>

**Editors:**
: Mike Deeb

**Abstract:**
This specification defines an abstract protocol for Extreme Programming (XP)
style pair programming conducted by autonomous software agents. It establishes
a model of *sessions*, *seats*, a single *session task*, *work phases*, *typed
advice*, and *lifecycle phases* that governs how agents collaborate on shared
artifacts. Each session has exactly one Driver, one Navigator, and one or more
Advisors; personas bind to agents and move with them when seats change. The
**Lead** frames the work (goal, initial roster, Session Task opening, and
amendments), handles lifecycle, retrospectives, and exceptions; **during
`active`**, the roster and **Session Runtime** manage routine coordination
through protocol tools and durable records, without the Lead on the hot path.
**Popcorn** (Driver-initiated transfer of the Driver seat, Section 9.2) is
peer-driven. The protocol requires no specific transport mechanism, storage
format, or agent runtime. Conformant implementations bind this abstract model to
concrete communication and persistence substrates.

**Status of This Document:**
This document is a Working Draft. It reflects the current understanding of the
editors and has not yet received wide review. Feedback is welcome.

---

## Table of Contents

1. [Introduction](#1-introduction)
2. [Conformance](#2-conformance)
3. [Terminology](#3-terminology)
4. [Sessions](#4-sessions)
5. [Seats](#5-seats)
6. [Agent Personas](#6-agent-personas)
7. [Session Task and Work Phases](#7-session-task-and-work-phases)
8. [Advice](#8-advice)
9. [Seat Assignment and Replacement](#9-seat-assignment-and-replacement)
10. [Session Lifecycle](#10-session-lifecycle)
11. [Persistence Requirements](#11-persistence-requirements)
12. [Communication Requirements](#12-communication-requirements)
13. [Conformance Summary](#13-conformance-summary)
14. [Appendix A: File-Bus Transport Binding (Non-Normative)](#appendix-a-file-bus-transport-binding-non-normative)
15. [Appendix B: Message-Passing Transport Binding (Non-Normative)](#appendix-b-message-passing-transport-binding-non-normative)
16. [Appendix C: TDD Integration (Non-Normative)](#appendix-c-tdd-integration-non-normative)

---

## 1. Introduction

Pair programming is a software development practice in which two programmers
work together at one workstation. One writes code while the other reviews each
line as it is written. The two switch roles frequently.

When the programmers are autonomous software agents rather than humans, the
practice retains its value but demands explicit coordination. Agents lack
shared visual context, cannot read body language, and operate under finite
context windows that degrade over time. They need a protocol.

This specification defines that protocol. It draws on Extreme Programming (XP)
discipline — particularly the practices of pair programming, test-driven
development, and structured handoffs — and adapts them for agents that
coordinate through messages and persistent records rather than shared screens
and conversation.

The protocol is transport-agnostic. It defines abstract primitives for
communication and persistence; conformant implementations bind those primitives
to concrete substrates (filesystems, message buses, shared databases, or any
combination). The normative sections of this specification constrain behavior
and invariants. The non-normative appendices illustrate how those constraints
might map to real systems.

### 1.1 Design Goals

1. **Safety through structure.** Exactly one Driver per session may modify the
   working tree at a time, and only during permitted **work phases** (Section
   7). Ownership is explicit. Advice is typed and tracked. These constraints
   prevent silent overwrites, lost context, and unreviewed changes.

2. **Quality through review.** The session has one Driver, one Navigator, and
   one or more Advisors; each agent keeps a stable **persona** (lens and
   duties) while **seats** change through **popcorn** (Section 9.2). The
   Navigator reviews the Driver's work as it happens; Advisors watch through
   distinct lenses. No artifact changes land without paired scrutiny plus
   advisory perspective.

3. **Resilience through persistence.** Agent context degrades. Agents crash.
   Sessions span hours. The protocol requires durable records that survive
   individual agent failures and enable seamless handoff to replacements.

4. **Portability through abstraction.** The protocol binds to no specific agent
   runtime, language model, or tool ecosystem. Any system that provides the
   required communication and persistence primitives can host a conformant
   session.

5. **PopcornXP governance — self-coordination under runtime invariants.** While a
   session is `active`, the roster coordinates through shared protocol tools
   (Checkpoint Log, Advice Ledger, Session Task State, Broadcasts, and related
   durable records). The **Session Runtime** enforces invariants (single writer,
   work-phase gates, OBJECTION gate on `complete`, and others in Section 13.1).
   The Lead is not in the hot path of routine peer coordination; see Section 3
   (**Lead**).

### 1.2 Scope

This specification defines:

- The abstract model of sessions, seats, a single session task, work phases,
  and advice
- The lifecycle of a collaborative session from creation to close
- The persistence and communication primitives that implementations must
  provide
- The behavioral obligations of conformant agents and runtimes

This specification does not define:

- How agents reason, plan, or generate code
- The format or encoding of persistent records
- The wire protocol of any transport mechanism
- Quality metrics, performance benchmarks, or success criteria for the
  work product

This specification treats **Lead failure recovery**, **session chaining** (linking
one session’s close to another’s open), and similar control-plane concerns as
**implementation-defined** for version 1.0. Implementations MAY support optional
metadata such as `predecessor_session_id` and `successor_session_id` on session
records.

Issue capture, roadmap work, and product planning are compatible with the Lead
role but are **outside** this protocol’s in-session coordination mechanism; they
do not replace Session Task state, the Advice Ledger, or runtime-enforced gates.

---

## 2. Conformance

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD",
"SHOULD NOT", "RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be
interpreted as described in [RFC 2119].

This specification defines two conformance classes:

**Conformant Session Runtime.**
An implementation that manages sessions, enforces seat invariants, provides the
required persistence and communication primitives, and gates lifecycle
transitions as specified. Section 13.1 enumerates the obligations.

**Conformant Agent.**
An agent whose behavior satisfies the seat obligations, advice lifecycle rules,
and task ownership constraints defined in this specification. Section 13.2
enumerates the obligations.

A conformant implementation may support additional features beyond those
specified here, provided those features do not violate any normative
requirement.

---

## 3. Terminology

The following terms carry specific meaning throughout this specification.

**Session.**
A bounded collaborative episode with a defined goal, an agent roster, a shared
working tree, and a lifecycle that progresses from creation to close.

**Seat.**
A role assignment governing an agent's obligations and permissions within a
session. There are three **seat kinds**: Driver (exactly one per session),
Navigator (exactly one), and Advisor (one or more).

**Lead.**
The coordinating entity in the **PopcornXP** model that creates the session,
defines the goal, assigns the **initial** roster (exactly one Driver, one
Navigator, one or more Advisors), binds personas to those agents, opens the
**Session Task**, may amend the Session Task per Section 7.7, and governs session
lifecycle (including retrospectives and close). The roster self-coordinates
during `active` work through protocol tools and durable records; the Session
Runtime enforces invariants (Section 13.1).

**Lead boundary (normative).** While the session **lifecycle** phase is
`active`, the Lead MUST NOT modify artifacts in the **working tree** and MUST
NOT intermediate **popcorn** or routine **work phase** transitions among roster
agents (Section 7.3, Section 9). The Lead MAY write issue records, planning
artifacts, retrospectives, and other protocol or control records outside the
session delivery write path (paths and record types are implementation-defined).
The Lead intervenes in active work only for escalation, deadlock,
abandonment disputes, forced-close, or other exceptions stated in this
specification.

The Lead may be a human operator, an orchestrating agent, or a runtime component.

**Popcorn.**
A **Driver-initiated** transfer of the Driver seat to another roster agent,
together with a deterministic reassignment so the former Driver occupies the
seat the incoming Driver vacated (Section 9.2). The Lead does not approve or
route popcorn.

**Session Task.**
The single unit of work for the session: a shared description, completion
criterion, write set, and optional ambiguity handling. Progress is tracked
through **work phases** (Section 7), not through a backlog of separate drive
and navigate tasks.

**Work Phase.**
The current stage of the Session Task (e.g., setup, aligning, ready,
driving, verifying, complete, abandoned). Work phases govern **when** the
Driver may edit and **when** the Navigator performs the verification tail.

**Advice.**
A typed, identifiable observation issued by one agent and targeting work
within the Session Task. Recorded in the Advice Ledger.

**Advice Ledger.**
The append-only persistent record of all advice entries and their resolutions
within a session.

**Checkpoint Log.**
The append-only persistent record of work progress, verification gate,
completion, abandonment, and handoff records within a session (Section 11.2).

**Artifact.**
Any file or resource in the shared working tree that agents read or modify.

**Working Tree.**
The shared set of artifacts that agents operate on during a session.

**Transport.**
The concrete mechanism by which agents exchange messages. Not specified by this
protocol.

**Persistence Substrate.**
The concrete mechanism by which session state is durably recorded. Not
specified by this protocol.

**Write Set.**
The declared set of artifacts that the Session Task allows the Driver to modify
while in `driving`. Edits outside the write set require a **Session Task
amendment** (Section 7.7) recorded in Session Task State before those edits are
permitted.

**Ready Artifact.**
A brief document published by the Navigator before implementation begins,
establishing the review scope. Valid types: risk assessment, test plan,
specification check, or review note.

**Verification Gate Checkpoint.**
A checkpoint log entry written when the Session Task leaves `driving` for
`verifying`: touched artifacts, verification status, open advice, and the
next identified risk.

**Handoff Record.**
A checkpoint log entry, written by an agent experiencing context degradation,
that records current seat, Session Task work phase, intended next action, key
context, open advice, and recommended starting point for a successor.

**Individual Retrospective Record.**
A persistent record of process observations (not task summaries) submitted by
**one** roster agent at session end, attributed to that agent.

**Primary Retrospective Record.**
The authoritative rollup for the session: process observations that
incorporate or explicitly reference each Individual Retrospective Record.
There is **exactly one** immutable Primary Retrospective per session.
**Preserved across sessions** means the implementation retains the **collection**
of per-session retrospectives (and optionally pointers between them), not that
a single rolling file appends unbounded sessions into one document.

**Retrospective Record** (generic).
Used when the distinction between individual and primary is not material.

**Persona.**
A reusable agent definition that declares an identity, a lens, a thinking
model, and behavioral boundaries. Personas map onto seats; the seat governs
protocol obligations, the persona governs perspective.

**Lens.**
A single orienting question that frames how a persona perceives the work. The
lens shapes what the agent notices and what advice it offers, but does not
restrict what the agent may act on.

---

## 4. Sessions

### 4.1 Session Structure

A Session comprises:

- A **goal**: a single statement that anchors scope. All task relevance is
  measured against the goal.
- A **roster**: the set of agents mapped to seats.
- A **working tree**: the shared artifacts agents operate on.
- A **session state**: the Checkpoint Log, Advice Ledger, per-agent state,
  Session Task state (work phase and metadata), and retrospective records.
- A **lifecycle phase**: one of `active`, `retro`, `closing`, or `closed`
  (see Section 10).

### 4.2 Session Invariants

1. A Session MUST have exactly one Lead.
2. A Session MUST have exactly one agent in the Driver seat, exactly one in the
   Navigator seat, and **at least one** agent in Advisor seats at all times while
   the session is not `closed` (a **minimum of three roster agents** in those
   seats). This **MUST** hold because the Advisor provides a perspective **outside**
   the Driver–Navigator pair; without it, review collapses to the pair alone.
   A future specification MAY define a separate **Lite** profile for two-agent
   sessions; this version does not.
3. A Session MUST define a goal and lock the **initial** persona-to-agent
   bindings before the Session Task leaves the `setup` work phase. Personas
   remain bound to **agents** across popcorn (Section 9.2); only seat
   assignments change.
4. The Checkpoint Log and Advice Ledger MUST be append-only. Implementations
   MUST NOT delete or reorder entries in these records.
5. A Session MUST NOT transition to `closed` until the Session Task has
   reached a terminal work phase and retrospective closeout is satisfied (see
   Section 10.2).
6. **No self-navigation** (Section 9.4): an agent MUST NOT occupy both Driver
   and Navigator seats, and MUST NOT be the sole reviewer of its own driven
   edits; violations require immediate signal to peers and the Lead.

---

## 5. Seats

Three seats govern how agents participate in a session. Each seat corresponds
to a temporal orientation: the Driver works on what is happening now, the
Navigator prepares for what comes next, and the Advisor reviews what already
happened.

### 5.1 Driver

The Driver is the **only** agent that may modify artifacts in the working tree,
and only while the Session Task work phase is `driving` (Section 7).

1. A Session MUST have exactly one Driver seat assignment at any time (the
   **single-writer invariant**).
2. The Driver MUST NOT modify any artifact unless the Session Task work phase
   is `driving`.
3. The Driver SHOULD constrain edits to the declared write set of the Session
   Task.
4. The Driver MAY reject non-blocking advice (SMELL, STEER, FYI) with stated
   reasoning.
5. The Driver MUST engage with every OBJECTION targeting the Session Task
   before the Session Task may enter the `complete` work phase.
6. The Driver MUST commit all pending artifact modifications before vacating the
   Driver seat (popcorn, Section 9.2, or degradation handoff, Section 9.3).
7. The Driver MAY initiate **popcorn** (Section 9.2) to pass the Driver seat to
   another roster agent without Lead involvement.

### 5.2 Navigator

The Navigator reads ahead of the Driver, reviews the approach, and issues
typed advice.

1. The Navigator MUST NOT modify artifacts in the working tree.
2. The Navigator MUST publish a Ready Artifact before the Driver begins
   implementation (the **readiness gate**). For a **trivial or unambiguous**
   increment, a **one-line review note** satisfies the Ready Artifact requirement
   (Section 7.4). The Navigator MAY propose use of this **fast path**; whether it
   applies is determined by **runtime policy**, without requiring Lead approval
   for that routine decision.
3. After publishing the Ready Artifact, the Navigator enters a monitoring
   phase: observing Driver progress and issuing further advice as warranted.
4. The Navigator SHOULD hold opinions loosely. OBJECTION is reserved for
   factual correctness, missed requirements, and defects — not stylistic
   preference.
5. While the Session Task is in `verifying`, the Navigator performs the
   **verification tail**: a **focused, read-only** review of the **current
   increment** (not an open-ended audit of the whole working tree), before work
   returns to `driving` or advances toward `complete`. The runtime MAY escalate
   or time out a stalled verification cycle per implementation policy.

### 5.3 Advisor

**Advisor seats.** A session has one or more Advisors. Each Advisor reviews
work through a **declared lens**; multiple Advisors provide *n* distinct
perspectives **independent of** the Driver–Navigator pair, satisfying the
minimum three-agent structure (Section 4.2).

1. An Advisor MUST NOT modify artifacts in the working tree.
2. Each Advisor observes through a declared **lens** (e.g., scope and
   constraints, verification, correctness) that shapes — but does not limit —
   what that Advisor may comment on.
3. Each Advisor SHOULD review each checkpoint in the Checkpoint Log and issue
   advice when its lens reveals a concern.
4. An agent assumes the Driver seat only when the current Driver initiates
   popcorn naming that agent as the incoming Driver (Section 9.2).

### 5.4 Seat Obligations Summary

| Property | Driver | Navigator | Advisor |
|---|---|---|---|
| May modify artifacts | YES (only in `driving`) | NO | NO |
| Count per session | Exactly 1 | Exactly 1 | One or more |
| Issues advice | MAY | MUST (primary obligation) | SHOULD (per seat) |
| Blocks on OBJECTION | MUST resolve before `complete` | N/A (issues them) | N/A (issues them) |
| Seat changes mid-session | Popcorn (§9.2); degradation handoff (§9.3) | Popcorn (§9.2); degradation handoff (§9.3) | Popcorn (§9.2); degradation handoff (§9.3) |

---

## 6. Agent Personas

Seats define protocol obligations. Personas define perspective. A persona is a
reusable agent definition that declares how an agent thinks, what it attends
to, and where it draws its boundaries — then maps onto a seat for the session.

### 6.1 Persona Structure

A persona definition MUST include:

1. **Identity.** A name and a one-sentence declaration: "You are `{name}`."
2. **Lens.** A single question that orients the agent's attention (e.g., "Is
   this clean and readable?" or "Does this actually work in edge cases?"). The
   lens frames what the agent notices first and what advice it is most likely
   to produce.
3. **Thinking model.** The questions the agent asks itself when examining work.
   These are not instructions to follow mechanically; they are the cognitive
   habits that make the persona's perspective distinct.
4. **Affirmative duties.** What the agent does when occupying a seat: the
   concrete actions that express its lens.
5. **Negative duties.** What the agent does not do: the boundaries that keep
   its focus sharp. One persona's negative duty is often another persona's
   affirmative duty ("Don't review style — that's the craftsman's lens").

A persona definition SHOULD include:

1. **Session behavior.** How the persona's perspective translates into specific
   seat conduct — what its checkpoints emphasize when driving, what its advice
   targets when navigating, what it watches for when advising.

### 6.2 Lens Semantics

The lens shapes attention; it does not impose limits.

An agent operating under the lens "How will we prove this works?" will notice
missing test coverage before noticing naming problems. An agent under "Is this
clean and readable?" will notice naming before noticing missing edge-case
tests. Both agents may comment on anything. The lens determines what they see
first, not what they are allowed to see.

A conformant implementation MUST declare a lens for each persona. The Lead
SHOULD select personas whose lenses complement rather than duplicate each
other.

### 6.3 Persona-to-Seat Mapping

Personas map onto seats; they do not replace them.

- Any persona MAY occupy any seat. A persona defined around correctness
  analysis can drive, navigate, or advise.
- The seat governs what the agent may do (Section 5). A persona occupying the
  Navigator seat MUST NOT modify artifacts, regardless of the persona's
  affirmative duties.
- The persona governs what the agent attends to. A correctness-focused persona
  navigating an implementation task brings edge-case awareness to the review;
  a cleanliness-focused persona navigating the same task brings structural
  awareness.

When the Lead assigns the initial roster, the Lead considers which lens best
serves each role. **Personas stay bound to agents**; **popcorn** (Section 9.2)
changes which agent holds which seat, so the same persona may drive, navigate,
or advise at different times without Lead involvement. The seat still governs
what the agent may do (Section 5) at each moment.

### 6.4 Negative Duties as Boundaries

Negative duties prevent persona drift. Each persona defines what it does not
do — and those boundaries typically reference another persona's lens:

- "Don't review style — that's the craftsman's lens."
- "Don't design tests — that's the tester's lens."
- "Don't drift into architecture commentary — that's the scout's lens."

These cross-references keep personas focused. Without them, every persona
converges toward the same generalist behavior, and the value of distinct
perspectives disappears.

A conformant implementation SHOULD define negative duties for each persona. The
negative duties SHOULD reference the persona whose lens covers the excluded
concern.

### 6.5 Thinking Model as Cognitive Fingerprint

The thinking model is what makes two personas with different lenses produce
genuinely different advice when shown the same code. It is a set of questions
the agent asks reflexively:

A correctness persona asks: "What happens with empty input? What state is
assumed but not validated? What invariant does this silently depend on?"

A cleanliness persona asks: "What's the simplest implementation that works?
Does this follow the existing patterns? Will someone reading this in six months
understand it?"

A scope persona asks: "What files are actually involved? What constraints
exist? Is the task scoped right?"

These questions are not checklists. They are habits of attention. A conformant
persona definition SHOULD express the thinking model as questions the agent
asks itself, not as procedures the agent executes.

### 6.6 Advice Style

A persona's lens and thinking model determine the texture of its advice:

- A persona focused on correctness issues OBJECTIONs when it finds a real
  bug ("that function doesn't handle the case where X is empty") and SMELLs
  when something looks suspicious but uncertain.
- A persona focused on cleanliness issues STEERs toward simpler alternatives
  ("there's already a helper for this in utils/") and SMELLs when naming
  obscures intent.
- A persona focused on scope issues STEERs when the task has drifted ("you're
  about to edit a file with twelve dependents") and FYIs when it discovers
  relevant constraints.

The advice types (Section 8.2) are shared across all personas. The lens
determines which types a persona reaches for most often and what evidence it
brings to each entry.

### 6.7 Persona Reuse and Composition

Personas are reusable across sessions. A conformant implementation SHOULD
maintain a roster of persona definitions that the Lead draws from when
assembling a team.

The Lead MAY substitute equivalent personas from external sources (e.g.,
domain-specific agents with their own behavioral definitions) provided the
substitute declares a lens, respects seat obligations, and follows the advice
lifecycle.

When a substitute persona lacks the protocol's collaboration rules, the Lead
SHOULD instruct it to load the protocol before its first action.

---

## 7. Session Task and Work Phases

### 7.1 Why work phases instead of task claims

Earlier drafts modeled **claims** on separate drive and navigate tasks. That
split confused implementers: two state machines had to stay synchronized,
and “claimed” did not distinguish *readiness to edit* from *permission to
edit*.

This specification uses **one Session Task** and a single **work phase**
enumeration. **Who may edit** is always: the Driver, and only in `driving`.
**When the Navigator verifies** is always: the `verifying` phase. No per-agent
claim on a second task is required.

### 7.2 Session Task contents

Each session has exactly one **Session Task**. It declares:

- An **identifier** (conventionally fixed for the session, e.g. `ST-1`).
- A **description** of what the session is building or changing toward the
  goal.
- A **completion criterion**: one sentence describing how to verify the Session
  Task is satisfied.
- A **write set**: the artifacts the Driver may modify while in `driving`.
- An optional **read set**: artifacts the Navigator should read ahead on.
- An optional **ambiguity flag** (see Section 7.5).

The Lead creates the Session Task when opening the session. The Lead MUST NOT
maintain a backlog of additional protocol-level tasks within the same session;
scope changes **amend** the single Session Task per Section 7.7 rather than
spawning parallel tasks.

### 7.3 Work phases

The Session Task occupies exactly one **work phase** at a time. Phases are
ordered for clarity; **allowed transitions** are what matter normatively.

| Phase | Driver may edit? | Navigator focus |
|---|---|---|
| `setup` | NO | Prepare; no implementation review yet |
| `aligning` | NO | Respond to approach; shape Ready Artifact |
| `ready` | NO | Ready Artifact published; gate before `driving` |
| `driving` | YES | Monitor; issue advice |
| `verifying` | NO | Verification tail (Section 5.2) |
| `complete` | NO | N/A (terminal) |
| `abandoned` | NO | N/A (terminal) |

**Normative work-phase graph.** Allowed transitions are exactly those below;
other transitions are prohibited unless this specification explicitly allows
runtime synthesis (Section 11.2).

| From | To |
|---|---|
| `setup` | `ready`, `aligning`, `abandoned` |
| `aligning` | `ready`, `abandoned` |
| `ready` | `driving`, `abandoned` |
| `driving` | `verifying`, `abandoned` |
| `verifying` | `driving`, `complete`, `abandoned` |

**Transition authority (normative).**

1. The Session Task MUST start in `setup`.
2. The Session Task MUST NOT enter `driving` until the Session Task is in `ready`
   and the Navigator has published the Ready Artifact (recorded per Section 5.2).
3. From `ready` to `driving`, the runtime MUST transition when **recorded
   prerequisites** are satisfied (Ready Artifact present, Session Task State
   consistent with policy, and any runtime-specific checks). **Lead approval**
   is **not** required for this routine transition.
4. From `driving` to `verifying`, the transition is **initiated by the Driver**
   (e.g., by requesting the transition and appending a Verification Gate
   Checkpoint, Section 11.2). The runtime applies the transition when the Driver’s
   request is valid.
5. From `verifying` to `driving`, `complete`, or `abandoned`, the outcome is
   **resolved by runtime policy** from **durable state** (Advice Ledger, Checkpoint
   Log, Session Task State). The Lead is **not** on the hot path for these
   routine resolutions; the Lead intervenes only for **escalation**, **deadlock**,
   **abandonment disputes**, or **forced-close** (Section 10).
6. The Session Task MUST NOT enter `complete` while any OBJECTION in the Advice
   Ledger targeting the Session Task remains unresolved. Unresolved OBJECTIONs
   **do not** block transition to **`abandoned`**.
7. Terminal phases are `complete` and `abandoned`; neither advances to a
   non-terminal phase except via session reset semantics outside this specification.

*Informative diagram (non-normative):*

```
setup → aligning? → ready → driving ⇄ verifying → complete
       \____________________________\____________→ abandoned
```

### 7.4 Checkpoints and increments

**Increments** are slices of work bounded by Progress Checkpoints and optional
Verification Gate Checkpoints. The work phase graph is **not** one checkpoint
per phase; multiple checkpoints typically occur while the phase remains
`driving`. Phases answer: *is editing allowed right now?* Checkpoints answer:
*what changed since last time?*

**Ready Artifact fast path.** When runtime policy classifies an increment as
**trivial or unambiguous**, the Navigator MAY satisfy the readiness gate with a
**one-line review note** as the Ready Artifact (Section 5.2). The Lead is not
required to approve use of the fast path.

### 7.5 Ambiguous scope

When the Session Task carries the **ambiguity flag**, the **first** transition
out of `setup` MUST be to **`aligning`** (not directly to `ready`). A
**design-alignment handshake** MUST complete before the first transition to
`driving`:

1. The Driver publishes a brief approach statement (recorded in the Checkpoint
   Log).
2. The Navigator publishes the Ready Artifact in response.
3. The runtime moves through `aligning` to `ready`, then `driving`, only after
   both are recorded.

Later, a transition from `verifying` back to `driving` **does not** require
entering `aligning` again **unless** a **material Session Task amendment**
(Section 7.7) changes the description, completion criterion, write set, read
set, or the ambiguity flag.

### 7.6 Scope shaping (non-normative)

The Lead and team SHOULD keep the Session Task description and write set
focused enough to reason about in one session. If scope explodes, prefer
**closing the session** and opening a new one with a new Session Task rather
than parallel in-session tasks.

### 7.7 Session Task amendments

Only the **Lead** or **designated planning policy** (implementation-defined,
e.g. automated scope rules) MAY amend the Session Task **description**,
**completion criterion**, **write set**, **read set**, or **flags** (including
the ambiguity flag). An amendment **takes effect** only after:

1. The amended values are recorded in **Session Task State**, and  
2. A **Progress Checkpoint** is appended to the Checkpoint Log noting the
   amendment (or an implementation-defined amendment record that satisfies the
   same durability and ordering rules).

**Write-set notification.** Any amendment that changes the **write set** MUST
trigger a **Broadcast** (Section 12.1) or an equivalent authoritative state
update. The **Driver** MUST observe the amended Session Task State before its
**next** artifact edit.

**Amendment timing.** Session Task amendments SHOULD NOT occur while the work
phase is `driving`. If they do, the Driver MUST **acknowledge** the amendment
(e.g., via a recorded acknowledgement, Peer Message, or Lead Signal per
implementation policy) before continuing edits.

---

## 8. Advice

### 8.1 Advice Entries

An advice entry is a typed, identifiable observation issued by one agent and
targeting work within the Session Task.

Each advice entry has:

- A **type**: one of OBJECTION, SMELL, STEER, or FYI.
- An **identifier**: scoped to the Session Task, following the pattern
  `{TYPE_PREFIX}-{session_task_id}-{sequence}` (e.g., `OBJ-ST-1-01`,
  `SML-ST-1-02`). Including **`session_task_id`** in the identifier is
  **required** for forward compatibility with future multi-task extensions.
- An **author**: the issuing agent.
- A **status**: `open` or `resolved`.
- A **body**: the observation, including artifact references where applicable.

### 8.2 Advice Types

Each type carries specific semantics and enforcement weight.

| Type | Semantics | Blocks Session Task `complete`? |
|---|---|---|
| **OBJECTION** | A claim that something is factually wrong, violates a requirement, or introduces a defect. | YES |
| **SMELL** | A concern that something looks off but may be acceptable. | NO |
| **STEER** | A suggestion for an alternative approach worth evaluating. | NO |
| **FYI** | Context or an observation worth noting. | NO |

Agents SHOULD reserve OBJECTION for factual correctness, missed requirements,
and defects. Overuse degrades the signal and turns the Navigator into a blocker
rather than a partner. When the concern is uncertain, agents SHOULD prefer
SMELL or STEER.

### 8.3 The Advice Ledger

The Advice Ledger is an append-only persistent record containing two entry
types:

1. **Advice entries** record the issuance of typed advice: type, identifier,
   author, body, and initial status `open`.
2. **Resolution entries** record the disposition of a previously open advice
   entry.

The Ledger MUST NOT be modified in place. Implementations append new entries;
resolutions reference the identifier of the entry they resolve.

An implementation derives the set of unresolved advice by computing which
advice entry identifiers lack a corresponding resolution entry.

### 8.4 Resolution

A resolution entry records:

- The **identifier** of the advice being resolved.
- An **outcome**: one of FIXED, REJECTED, INCORPORATED, or NOTED.
- A **detail**: what was done or why the outcome was chosen.

| Outcome | Meaning |
|---|---|
| **FIXED** | The issue was corrected. |
| **REJECTED** | The agent disagrees and provides reasoning. |
| **INCORPORATED** | The suggestion was adopted. |
| **NOTED** | The observation was acknowledged. |

REJECTED is a first-class outcome. An agent who rejects an OBJECTION with
sound reasoning has used the protocol correctly.

### 8.5 Resolution Invariants

1. Each advice entry MUST be resolved at most once (the **single-resolver
   rule**). Before appending a resolution, an agent MUST verify that no
   resolution for that identifier already exists in the Ledger.
2. When the Session Task enters `complete` with resolved OBJECTIONs, the
   **Completion Checkpoint** (Section 11.2) MUST explicitly reference each
   OBJECTION resolution: identifier, outcome, and summary.
3. **Re-raising resolved advice.** An agent MUST NOT re-open a resolved advice
   **identifier**. To raise the same concern again, it MUST append a **new**
   advice entry with a **new** identifier and **new** evidence.

### 8.6 Advice as Input

Advice is input, not instruction.

- Agents MUST engage with OBJECTIONs.
- Agents SHOULD be aware of open SMELL, STEER, and FYI entries.
- Agents are NOT obligated to comply with non-blocking advice. They are
  obligated to be aware of it.

*Note: The intended dynamic is "strong opinions, loosely held." A Driver who
says "I considered that, but my approach is better because X" and a Navigator
who says "fair enough" have both used the system correctly.*

---

## 9. Seat Assignment and Replacement

### 9.1 Initial assignment

At session start the Lead MUST:

1. Assign exactly one Driver, one Navigator, and one or more Advisors from the
   roster.
2. Bind a **persona** to each **agent** (identity, lens, duties) and record the
   bindings in persistent Agent State.
3. Open the Session Task in the `setup` work phase.

The Lead MUST NOT operate a queue of protocol-level tasks or intermediate
routine seat changes after `setup`. Ongoing work is always the single Session
Task. **Popcorn** (Section 9.2) is how roster agents change seats during
`active` work.

### 9.2 Popcorn (Driver-initiated seat transfer)

**Popcorn** passes the keyboard without Lead involvement. Only the **current**
**Driver** MAY initiate popcorn.

**Eligible incoming Driver.** The incoming Driver MUST be the agent who
**currently** holds the Navigator seat or a specific Advisor seat (identified
unambiguously in implementation, e.g., advisor slot id).

**Atomic reassignment.** When popcorn commits, the runtime MUST apply **both**
updates atomically (or equivalent serializability):

1. The **incoming** agent becomes the Driver.
2. The **outgoing** Driver assumes the seat vacated by the incoming agent
   (Navigator or the same Advisor slot).

All other roster agents keep their current seats. Invariants from Section 4.2
MUST hold before the commit is visible.

**Notifications and polling.** After popcorn is committed, the runtime MUST
either:

- **Broadcast** a seat-change event to all roster agents, **or**
- Expose updated Agent State such that conformant agents are required to read
  it (Section 13.2).

Every agent whose seat changed MUST treat the change as authoritative before
acting in a new capacity.

**Follow-on responsibility.** The outgoing Driver (now Navigator or Advisor)
SHOULD immediately confirm their new seat in Agent State (or acknowledge the
Broadcast). Any roster agent that learns its seat changed without having
initiated the change MUST read Agent State (or process the Broadcast) **before**
its next normative protocol action (advice, edits, phase transitions). Agents
MAY **popcorn** further roles among themselves only as allowed by this
specification: only the **current Driver** may initiate the **next** popcorn
(Driver seat transfer). A former Driver who now holds the Navigator seat cannot
pass the Driver seat until they become Driver again; they MAY use Peer
Messages to **request** that the current Driver popcorn, but cannot force it.

**Checkpoint.** The initiating Driver SHOULD append a Progress Checkpoint to
the Checkpoint Log describing popcorn: outgoing and incoming Driver identities
and seat swap.

**Work phase.** The new Driver MUST NOT modify artifacts until the Session
Task work phase is `driving` and they have observed their seat assignment.

**Anti-stalemate.** Runtimes MAY **rate-limit** repeated **popcorn** cycles that
produce **no intervening progress** (e.g., no Progress Checkpoint or no durable
state change between swaps) and MAY **escalate** such patterns as an exception
for Lead or operator handling.

### 9.3 Replacement and handoff (degradation)

When an agent is retired (context degradation, failure, or policy), a
**successor** agent MAY assume the same seat and persona binding. This path
is **not** popcorn; it exists so runtimes can replace a crashed process. The
Lead MAY spawn or designate a successor, or peers MAY agree out of band—this
specification does not require Lead approval for the **seat** reassignment
during degradation, but implementations often route process spawn through the
Lead.

The outgoing agent MUST:

1. Commit all pending artifact modifications if it holds the Driver seat.
2. Record a Handoff Record (Section 11.2) with current seat, Session Task work
   phase, intended next action, key context, open advice, and a recommended
   starting point for the successor.
3. Signal peers (Lead Signal or Broadcast as appropriate).

The successor MUST reconstruct state from persistent records (Section 10.4)
before acting.

**Hard-crash recovery.** If an agent cannot write its own **Handoff Record**,
the runtime MAY append a **synthesized** Recovery or Handoff checkpoint derived
from durable state so a successor can take over safely. The Lead MAY request or
authorize that exception path; the Lead is **not** required for routine
degradation handling where policy allows synthesis.

### 9.4 No self-navigation

If a bug or misconfiguration places the same agent in both Driver and
Navigator roles, or causes an agent to review only its own edits, the agent
MUST signal peers and the Lead immediately. Implementations SHOULD forbid
overlapping Driver and Navigator assignments. (Session invariant, Section 4.2.)

### 9.5 Lead and seat changes

The Lead MUST NOT routinely reassign seats during `active` work; **popcorn**
(Section 9.2) is the normative mechanism. The Lead’s seat-related obligations
are limited to **initial** assignment (Section 9.1) and operational concerns
outside this specification (e.g., tearing down a broken session).

---

## 10. Session Lifecycle

### 10.1 Lifecycle Phases

A session progresses through four phases:

```
active -> retro -> closing -> closed
```

| Phase | Entry Condition | Lead Obligations | Agent Obligations |
|---|---|---|---|
| `active` | Session created; goal, roster, personas, and Session Task defined | Frame scope and exceptions; do **not** intermediate routine popcorn (§9.2) or routine work-phase changes (Section 7.3); do **not** edit the working tree (Section 3) | Fulfill seat obligations; **popcorn** Driver seat per §9.2 when passing the keyboard; issue and resolve advice |
| `retro` | Session Task terminal (`complete` or `abandoned`), or Lead initiates early | Request an Individual Retrospective from each roster agent; produce the Primary Retrospective rollup | Submit Individual Retrospective focused on process |
| `closing` | All Individual Retrospectives submitted and Primary Retrospective recorded | Verify closeout preconditions; initiate close | Cease work; approve shutdown |
| `closed` | Closeout preconditions satisfied; close executed | None (session is immutable) | None (session is immutable) |

### 10.2 Closeout Preconditions

A Session MUST NOT transition from `closing` to `closed` until:

1. The Session Task has reached a terminal work phase (`complete` or
   `abandoned`).
2. If the terminal work phase is **`complete`**, no OBJECTION in the Advice
   Ledger that targets the Session Task remains unresolved. If the terminal work
   phase is **`abandoned`**, unresolved OBJECTIONs MUST NOT be treated as blocking
   closeout.
3. Each roster agent (Driver, Navigator, every Advisor) has submitted an
   Individual Retrospective Record whose required fields (Section 10.3) are
   **non-empty**.
4. A Primary Retrospective Record exists whose required fields (Section 10.3)
   are **non-empty** and that explicitly incorporates or references every
   Individual Retrospective Record for the session.

An implementation MAY provide a forced-close mechanism that bypasses these
preconditions but MUST record that the close was forced.

### 10.3 Retrospective Records

**Individual Retrospective Records.** Each roster agent submits its own record:
**process observations**, not task summaries. Each record MUST include
**non-empty** machine- or human-readable fields (implementation-defined shape)
for:

- **`what_worked`**
- **`what_hurt`**
- **`suggested_change`**

**Content quality** (depth, insight, length) is a **SHOULD**, not a
machine-gated **MUST**. Additional themes are encouraged:

- What worked well about the pairing and advisory dynamic.
- What made collaboration harder.
- Whether the advice system helped or impeded progress.
- Whether checkpoints were frequent enough for useful navigation.
- What should change about seat assignments, personas, or Session Task shaping.

**Primary Retrospective Record.** The Lead (or a delegate) writes the
**single** authoritative rollup for the session (Section 3, Section 10.2). It MUST:

- Include **non-empty** `what_worked`, `what_hurt`, and `suggested_change`
  fields at the rollup level (same structural rule as Individual Retrospectives),
- Explicitly reference or embed each Individual Retrospective (e.g., by agent
  id and pointer or quoted summary), and
- **SHOULD** provide substantive synthesis across the team (quality is not a
  hard gate).

The Primary Retrospective for the session is the durable artifact **for that
session**; the implementation preserves **per-session** retrospectives across
sessions as a collection (Section 3). Individual Retrospectives SHOULD be
preserved as well for auditability.

### 10.4 Context Degradation and Handoff

Agents operating under finite context windows may experience degradation during
long sessions. The protocol defines a handoff mechanism:

1. The degrading agent writes a Handoff Record (Section 11.2) containing:
   current seat, Session Task work phase, intended next action, key context,
   open advice, and recommended starting point for a successor.
2. The agent signals the Lead and its current partner.
3. The agent completes its current atomic operation, records final state, and
   stops.
4. The Lead MAY retire the agent and spawn a fresh agent initialized from the
   Handoff Record and the session's persistent state.

**Post-discontinuity recovery.** After any context discontinuity (compaction,
restart, or handoff), an agent MUST reconstruct state from persistent records
before resuming work:

1. Read the Checkpoint Log for latest progress.
2. Read the Advice Ledger for open items.
3. Check Session Task state for the current work phase and metadata.
4. Review recent artifact history.

An agent MUST NOT re-execute work already recorded as complete.

---

## 11. Persistence Requirements

### 11.1 Required Persistent Records

A conformant Session Runtime MUST provide durable storage for the following
records. This specification defines their semantics, not their format or
storage location.

| Record | Mutability | Purpose |
|---|---|---|
| Checkpoint Log | Append-only | Ordered record of typed entries: progress, verification gate, completion, abandonment, and handoff records (Section 11.2) |
| Advice Ledger | Append-only | Typed advice entries and their resolutions; supports open/resolved derivation |
| Individual Retrospective Record | Append-one per agent | Process observations from one roster agent for the session |
| Primary Retrospective Record | Append-only | Rollup incorporating all Individual Retrospectives; preserved across sessions |
| Agent State | Mutable | Current seat, **implementation-defined status** (runtime-local; e.g. bench, waiting-on-driver), persona binding, and (for Driver) write set awareness |
| Session Task State | Mutable | Current work phase, Session Task metadata (description, criterion, write set, flags) |

### 11.2 Checkpoint Log Entry Types

The Checkpoint Log accommodates the entry types below. All are append-only and
ordered.

**Checkpoint authorship (normative).** The **Driver** normally appends
**Progress**, **Verification Gate**, **Completion**, and **Abandonment**
checkpoints. The **Navigator** publishes **Ready Artifacts** and **Advice
Ledger** entries; the Navigator does **not** append Checkpoint Log entries. A
**degrading agent** writes a **Handoff Record** when possible. The **Lead** (or
delegate) writes the **Primary Retrospective** (Section 10.3), not Checkpoint Log
entries for routine work. If the Driver is **absent** or cannot write, the
runtime MAY **synthesize** the required **Completion** or **Abandonment**
checkpoint (and, under Section 9.3, Recovery/Handoff) from durable state; the
Lead MAY request or authorize that path but is **not** required for routine
flow where policy allows synthesis.

**Progress Checkpoint.**
Records a unit of completed work: artifacts modified, tests run, advice
resolved. The Navigator and Advisor observe these entries as review points.

**Verification Gate Checkpoint.**
Records transition from `driving` to `verifying`: touched artifacts,
verification status, open advice, and the next identified risk. Normally written
by the Driver at the gate.

**Completion Checkpoint.**
Records transition of the Session Task to terminal phase **`complete`**, and
MUST satisfy Section 8.5 for OBJECTION references when applicable.

**Abandonment Checkpoint.**
Records transition of the Session Task to terminal phase **`abandoned`**
(including reason and pointers to durable state as required by implementation
policy).

**Handoff Record.**
Records context for agent replacement: current seat, Session Task work phase,
intended next action, key context, open advice, and recommended starting point.
Written by a degrading agent when possible (Section 9.3 for synthesis).

An implementation MAY distinguish entry types through metadata, schema, or
convention.

### 11.3 Durability

Persistent records MUST survive individual agent failures. An agent crash or
retirement MUST NOT cause loss of entries recorded before the failure.

Ephemeral communication (Section 12) is NOT required to be durable.
Implementations SHOULD treat ephemeral channels as lossy and record critical
state transitions in persistent records.

### 11.4 Consistency

When multiple agents access shared persistent records concurrently, the
implementation MUST guarantee:

1. **Read-after-append.** An agent reading an append-only record observes all
   entries whose append completed before the read began.
2. **Write exclusivity.** At most one agent (the Driver) may perform artifact
   modifications in the working tree at a time, and only while the Session Task
   work phase is `driving`. The runtime MUST reject edits that violate this rule.
3. **Append ordering.** Entries in append-only records appear in the order they
   were appended.

The required consistency model is **intentionally weaker** than full
**linearizability**: **read-after-append** plus **ordered append** for the
append-only records is sufficient. This specification does not mandate a specific
concurrency mechanism. Locks, compare-and-swap, serialized writes, or any
other approach that satisfies these properties is acceptable.

---

## 12. Communication Requirements

### 12.1 Communication Primitives

A conformant Session Runtime MUST provide the following abstract communication
primitives. This specification defines their delivery semantics, not their
transport mechanism.

| Primitive | Sender | Receiver(s) | Purpose |
|---|---|---|---|
| **Peer Message** | Any agent | One specific agent | Tactical discussion within the session: approach, questions, advice negotiation |
| **Lead Signal** | Any agent | The Lead | Escalation, anomaly reporting, handoff notification, work-phase readiness |
| **Broadcast** | Lead or any agent | All session agents | State transitions, session-wide announcements, shutdown initiation |

### 12.2 Delivery Guarantees

**Peer Messages.**

- Messages from a single sender SHOULD be delivered in the order sent.
  Cross-sender ordering is NOT required.
- Peer Messages are ephemeral. An implementation MAY drop messages under
  resource pressure. Agents MUST NOT rely on message history surviving across
  context discontinuities. Anything that must survive belongs in a persistent
  record (Section 11).

**Lead Signals.**

- A signal from an agent to the Lead MUST be delivered. Lead Signals MUST NOT
  be silently dropped.

**Broadcasts.**

- A Broadcast MUST be delivered to all agents active at the time of broadcast.
  Delivery to agents that join after the broadcast is NOT required.
- Seat-change Broadcasts after **popcorn** (Section 9.2) SHOULD include enough
  detail (or a pointer to Agent State) that every roster agent can update its
  understanding of who holds Driver, Navigator, and each Advisor slot.

### 12.3 Relationship to Persistence

Communication and persistence are complementary, not redundant.

- **Tactical discussion** flows through Peer Messages. It is fast, ephemeral,
  and bilateral.
- **Durable decisions** flow through persistent records. Advice is negotiated
  via Peer Messages but recorded in the Advice Ledger. Progress is discussed
  via Peer Messages but recorded in the Checkpoint Log.

An agent MUST NOT treat a Peer Message as a substitute for a persistent record.
If a state transition matters beyond the current exchange, the agent MUST
record it.

### 12.4 Channel Binding

This specification does not prescribe how primitives map to concrete channels.
A conformant implementation might bind:

- Peer Messages to direct inter-process messaging, file-backed chat logs, or
  shared message queues.
- Lead Signals to the same mechanism or a dedicated control channel.
- Broadcasts to fan-out over peer channels, a shared event log, or a pub/sub
  system.

The non-normative appendices illustrate example bindings.

---

## 13. Conformance Summary

### 13.1 Conformant Session Runtime

A conformant Session Runtime MUST:

1. Manage session lifecycle through the four phases defined in Section 10.1.
2. Enforce the single-writer invariant (Section 5.1): at most one agent holds
   the Driver seat at any time.
3. Enforce write exclusivity (Section 11.4): only the Driver may modify
   artifacts, and only while the Session Task work phase is `driving`.
4. Provide durable storage for all required persistent record types
   (Section 11.1) with the append-only, durability, and consistency guarantees
   of Sections 11.2 through 11.4.
5. Provide all three communication primitives (Section 12.1) with the delivery
   guarantees of Section 12.2.
6. Enforce the OBJECTION gate: block transition of the Session Task to
   `complete` while unresolved OBJECTIONs exist in the Advice Ledger for that
   Session Task. Unresolved OBJECTIONs MUST NOT block transition to
   **`abandoned`**.
7. Enforce closeout preconditions (Section 10.2) before transitioning to
   `closed` (including structural retrospective fields and, when the terminal
   work phase is `complete`, resolved OBJECTIONs).
8. Preserve Primary Retrospective Records (and SHOULD preserve Individual
   Retrospective Records) across sessions.
9. Support **popcorn** (Section 9.2): atomic Driver-seat transfer plus
   vacated-seat fill, without Lead approval.
10. After each popcorn, deliver a **Broadcast** of seat changes **or** document
    that agents MUST read Agent State before acting (Section 13.2).

A conformant Session Runtime SHOULD:

1. Enforce write-set constraints: warn or block when a Driver modifies
   artifacts outside the declared write set.
2. Provide a mechanism for detecting context degradation and initiating
   handoff.
3. Provide a forced-close mechanism that records the override.
4. Warn agents of open non-blocking advice (SMELL, STEER, FYI) at Session Task
   boundaries (e.g., `verifying` or `complete`).

A conformant Session Runtime MAY:

1. Provide artifact-level soft locking for cross-agent read/edit awareness.
2. Support agent retirement and replacement via Handoff Records.

### 13.2 Conformant Agent

A conformant Agent MUST:

1. Respect its seat: a Navigator or Advisor MUST NOT modify artifacts in the
   working tree.
2. Respect work phases: only the Driver may modify artifacts, and only in
   `driving`.
3. Engage with every OBJECTION targeting the Session Task before it may reach
   `complete` while that agent holds the Driver seat.
4. Reference each resolved OBJECTION (identifier, outcome, summary) in the
   **Completion Checkpoint** (Section 11.2) when the Session Task reaches
   `complete`.
5. Commit all pending artifact modifications before vacating the Driver seat.
6. Reconstruct state from persistent records after any context discontinuity.
7. Not re-execute work already recorded as complete.
8. **Overwrite rule.** A conformant Agent MUST NOT overwrite another agent’s work
   without **first reading** the **current** artifact state. When recent
   **checkpoints** or **open advice** reference that artifact, the agent SHOULD
   review that context before editing.
9. Record state transitions in persistent records, not only in ephemeral
   messages.
10. Not navigate the review of its own driven work (Section 9.4).
11. After a seat change affecting this agent (e.g., popcorn, Section 9.2),
    observe the Broadcast or read Agent State **before** the next normative
    protocol action so role obligations match current seats.

A conformant Agent SHOULD:

1. Publish a Ready Artifact before the Driver begins implementation
   (Navigator).
2. Review each checkpoint through its declared lens (Advisor).
3. Prefer SMELL or STEER over OBJECTION when the concern is uncertain.
4. Declare intent before going idle or switching focus.
5. Write a Handoff Record when experiencing context degradation.
6. Constrain edits to the declared write set.
7. Check recent artifact history before editing shared artifacts.
8. Submit an Individual Retrospective Record when requested (each Advisor
   submits a distinct record).

A conformant Agent MAY:

1. Reject non-blocking advice with stated reasoning.
2. Reject an OBJECTION with stated reasoning (REJECTED is a first-class
   outcome).
3. Read ahead within artifacts declared in the Session Task read set or write
   set while in `active`.

---

## Appendix A: File-Bus Transport Binding (Non-Normative)

*This appendix illustrates how the abstract model might bind to a file-backed
transport where agents coordinate through a shared filesystem. This is one
conformant approach; others are equally valid.*

### A.1 Persistence Binding

| Abstract Record | File Binding |
|---|---|
| Checkpoint Log | A Markdown file with one section for the Session Task and one subsection per checkpoint entry. |
| Advice Ledger | A Markdown file with advice entries as headings (e.g., `### OBJECTION OBJ-ST-1-01 — open`) and resolution entries as headings (e.g., `### OBJ-ST-1-01 — FIXED`). The unresolved set is computed by scanning for advice headings without matching resolution headings. |
| Individual Retrospective Record | One Markdown (or JSON) file per roster agent per session, append-once. |
| Primary Retrospective Record | One Markdown (or JSON) file **per session** containing the rollup; implementations preserve **collections** of session retrospectives across time (Section 3). |
| Agent State | One JSON file per agent, mutable. Fields: seat, **implementation-defined status** (runtime-local; not normative work phases), persona id, optional write-set cache for Driver. |
| Session Task State | One JSON (or YAML) file, mutable. Fields: work phase, identifier, description, completion criterion, write set, read set, flags. |

All files reside under a session directory scoped to the team name.

### A.2 Communication Binding

| Abstract Primitive | File-Bus Binding |
|---|---|
| Peer Message | Append to a per-task chat file via a session helper. Per-agent read cursors track consumption. |
| Lead Signal | The Lead reads persistent records and agent state files directly. Agents signal through state changes and chat entries. |
| Broadcast | Signal files or a shared event snippet (e.g., shutdown, retro-request, **popcorn** seat snapshot) that agents detect on their next action; popcorn updates MAY be written by a session helper on behalf of the Driver. |

### A.3 Session Task state and work-phase transitions

Work-phase transitions are implemented as atomic writes to the Session Task
State file. An optional compare-and-swap mechanism uses a revision counter:
the agent reads the current revision, then passes it as an expected-revision
argument to the transition operation. The transition fails if the revision has
advanced. The session helper MUST reject illegal transitions (e.g., `driving`
without a prior `ready`).

### A.4 Popcorn (roster update)

**Popcorn** updates every affected `agent-state` file (or a single roster JSON)
in **one** atomic step—e.g., write to a temp file and rename, or transactional
store—so no observer sees an intermediate state with two Drivers or zero
Navigators. The session helper SHOULD append a Progress Checkpoint and MAY
write a small `popcorn` broadcast marker for watchers.

### A.5 OBJECTION Gate

A session helper scans the Advice Ledger file for OBJECTION headings scoped to
the Session Task identifier. If any such heading lacks a corresponding
resolution heading, transition to work phase `complete` is blocked with a
diagnostic message. Transition to **`abandoned`** is **not** blocked by
unresolved OBJECTIONs.

### A.6 Lifecycle Signals

| Lifecycle Event | Signal Mechanism |
|---|---|
| Retro requested | Lead writes a retro-request signal file. |
| Individual retro submitted | Each agent writes its Individual Retrospective file. |
| Primary retro recorded | Lead writes or appends the Primary Retrospective file. |
| Shutdown initiated | Lead writes a shutdown signal file. |
| Session closed | Session helper writes a closed marker and cleans up the active-session pointer. |

---

## Appendix B: Message-Passing Transport Binding (Non-Normative)

*This appendix illustrates how the abstract model might bind to a transport
where agents exchange messages through a runtime-managed message bus. This is
one conformant approach; others are equally valid.*

### B.1 Persistence Binding

Persistent records use the same file-backed approach as Appendix A.1. The
message-passing layer handles communication; persistence remains file-backed.

An alternative implementation could back persistent records with a database, a
distributed log, or any substrate that satisfies the durability and consistency
requirements of Section 11.

### B.2 Communication Binding

| Abstract Primitive | Message-Passing Binding |
|---|---|
| Peer Message | Direct agent-to-agent message delivery via the runtime. Messages deliver automatically; no polling or file-watching required. |
| Lead Signal | Direct message to the Lead agent. The runtime guarantees delivery. |
| Broadcast | The Lead sends individual messages to each active agent, or the runtime provides a broadcast primitive. |

### B.3 Session Task state and edits

The runtime enforces write exclusivity: artifact edits succeed only from the
Driver identity while the Session Task work phase is `driving`. Work-phase
updates use a primitive with mutual exclusion or optimistic concurrency.

### B.4 OBJECTION Gate

The gate operates on the persistent Advice Ledger, not on ephemeral messages.
The transport affects how agents *discuss* advice; it does not affect how the
gate *evaluates* it.

### B.5 Lifecycle Signals

| Lifecycle Event | Signal Mechanism |
|---|---|
| Retro requested | Lead sends a message to each agent requesting a Retrospective Record. |
| Individual retro submitted | Agent writes its Individual Retrospective and confirms via message. |
| Primary retro recorded | Lead writes the Primary Retrospective and confirms via message. |
| Shutdown initiated | Lead broadcasts shutdown; agents acknowledge via message. |
| Session closed | Lead marks the session closed through the runtime. |

### B.6 Idle Enforcement

The runtime MAY provide an idle-detection mechanism that fires when an agent
has not acted within a defined interval. The idle handler's behavior depends on
the agent's **implementation-defined status** in Agent State (Section 11.1);
values such as `waiting_on_driver` or `bench` are **runtime-local** and are **not**
normative Session Task work phases:

| Status (informative examples) | Idle Response |
|---|---|
| `driving` or `navigating` | Nudge the agent to continue work. |
| `waiting_on_driver` | Nudge the agent to review recent activity. |
| `bench` or `shutdown` | Suppress the nudge. |
| Retro pending | Nudge the agent to submit a Retrospective Record. |

---

## Appendix C: TDD Integration (Non-Normative)

*This appendix describes how the Test-Driven Development (TDD) cycle
integrates with the pair-programming protocol. TDD is not required for
conformance.*

### C.1 Red-Green-Refactor as Checkpoint Rhythm

Each TDD iteration maps to a natural checkpoint in the protocol:

| TDD Phase | Protocol Event |
|---|---|
| **Red** — write a failing test | Progress checkpoint. Records the design decision: what the code *should* do. Navigator advice point: STEER if the wrong behavior is targeted. |
| **Green** — write the minimal code that passes | Progress checkpoint. Records the implementation. Navigator advice point: OBJECTION if the implementation does not satisfy the requirement. |
| **Refactor** — clean up under green tests | Progress checkpoint. Records the cleanup. Navigator advice point: SMELL if the refactoring reduced clarity. |

The Red-Green-Refactor rhythm creates frequent, small checkpoints — the
granularity that makes navigation and advice most effective.

### C.2 TDD under a single Driver

Because exactly one Driver may edit (Section 5.1), ping-pong TDD stays **role-
stable**: the **Driver** performs Red, Green, and Refactor while the work phase
remains `driving`. The **Navigator** issues STEER/OBJECTION/SMELL at each
checkpoint (Section C.1) but does not take the keyboard. If the team wants a different agent to implement the next increment, the
**current Driver** initiates **popcorn** (Section 9.2) to pass the Driver seat;
the Lead does not intermediate.

---

## References

### Normative References

**[RFC 2119]**
Bradner, S., "Key words for use in RFCs to Indicate Requirement Levels",
BCP 14, RFC 2119, March 1997.

### Informative References

**[XP]**
Beck, K., *Extreme Programming Explained: Embrace Change*, Addison-Wesley,
1999.

**[TDD]**
Beck, K., *Test-Driven Development: By Example*, Addison-Wesley, 2002.

**[PAIR]**
Williams, L. and Kessler, R., *Pair Programming Illuminated*,
Addison-Wesley, 2002.
