---
name: popcorn-xp-team
description: "Use when the user explicitly wants Popcorn XP with **native Claude Agent Teams** (coordinator lead, TaskUpdate, SendMessage, context-store hooks). Matches **popcorn-xp-team** plugin. For default file-bus workflow, use **popcorn-xp** plugin + **popcorn-xp** skill."
# disable-model-invocation: true
---

**Transport:** **`popcorn-xp-team`** plugin. Set **`.runtime-mode`** to **`team`**. Enable at most one of **`popcorn-xp`** and **`popcorn-xp-team`** in Claude Code (duplicate hooks if both are on).
