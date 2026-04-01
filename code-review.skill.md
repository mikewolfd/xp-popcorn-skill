---
name: code-review
description: Use when the user asks to review code changes, a PR, a diff, or a patch. Performs a structured, evidence-based code review producing a formal certificate with function traces, data flow analysis, invariant checking, edge case enumeration, and a verdict. Triggers on phrases like "review this PR", "review these changes", "code review", "review the diff", or "check this patch".
---

# Code Review

Perform a structured, evidence-based code review using the `popcorn-xp:code-reviewer` agent. This skill produces a formal review certificate — not a casual skim — by tracing functions, analyzing data flow, checking invariants, and enumerating edge cases.

## Trigger

Activate when the user asks for a code review:

- "review this PR"
- "review these changes"
- "do a code review"
- "check this diff"
- "review the patch"
- "what do you think of these changes?"

Do not activate for general code questions or explanations. This is for reviewing changes against a codebase.

## Workflow

### 1. Identify the Changes

Determine what to review based on the user's request:

- **PR number**: Fetch the PR diff using GitHub MCP tools (`mcp__github__get_pull_request`, `mcp__github__get_pull_request_diff`)
- **Branch comparison**: Run `git diff <base>...<head>` to get the changes
- **Staged changes**: Run `git diff --cached` for staged changes
- **Unstaged changes**: Run `git diff` for working tree changes
- **Specific commits**: Run `git diff <commit1>..<commit2>` or `git show <commit>`

If the user doesn't specify, check for uncommitted changes first, then ask.

### 2. Launch the Code Reviewer

Spawn the `popcorn-xp:code-reviewer` agent with the diff and context:

```
Agent(
  name: "code-reviewer",
  prompt: "Review the following code changes against this repository.

## Changes to Review

<diff>
{the diff content}
</diff>

## Context
- Repository: {repo name/path}
- PR/Branch: {if applicable}
- Stated intent: {PR description, commit message, or user's description of what the changes do}

## Instructions

Follow your exploration protocol. Read every file touched by the diff, trace functions at least one level deep in each direction, and produce the full review certificate. Do not skip any section.

Begin by examining the diff, then explore the repository methodically. Produce the complete certificate before giving your verdict."
)
```

### 3. Present Results

When the agent completes:

1. **Lead with the verdict** — APPROVE, REQUEST CHANGES, or NEEDS DISCUSSION
2. **Summarize findings** — list BLOCKERs and WARNINGs with file:line references
3. **Include the full certificate** — the user needs the evidence chain, not just the conclusion
4. **If reviewing a PR**: Offer to post findings as a PR review comment (only if the user asks)

## Quality Bar

- Every claim in the review must cite a specific file and line number
- Every function touched by the diff must appear in the function trace table
- Edge cases must be concrete scenarios, not vague "what if" hand-waving
- The verdict must follow from the evidence, not precede it
- If a section of the certificate cannot be filled, that gap is itself a finding
