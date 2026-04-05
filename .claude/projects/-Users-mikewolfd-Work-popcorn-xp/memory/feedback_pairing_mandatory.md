---
name: Never spawn solo drivers
description: Phase 1 of the layout audit ran 4 solo drivers with zero navigators — user called this the primary protocol violation. Navigators are the quality mechanism, not overhead.
type: feedback
---

Never spawn solo drivers, even for parallel throughput. The 2026-04-04 session ran 4 independent drivers with zero navigators in Phase 1. Every bug caught was found retroactively by experts reviewing after the fact, not during implementation.

**Why:** User's primary criticism: "the entire point is that they take turns in navigator/driver teams." Phase 2 with proper pairs found real bugs in every task. Phase 1 had zero advice and zero bugs caught during implementation.

**How to apply:** Enforce driver+navigator pairing from task 1. The lead must pair every driver before work starts. Never optimize parallelism over pairing — pairing IS the quality mechanism.
