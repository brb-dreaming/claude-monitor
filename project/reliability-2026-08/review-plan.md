# Full Review Plan

## Review tracks

### A — Baseline and change control

Capture repository state, build environment, supported-OS claims, dirty changes,
and reproducible non-destructive checks.

### B — Session state and persistence

Map producers and consumers; analyze event ordering, atomicity, lost updates,
malformed data, cleanup, recovery, and schema evolution.

### C — Permission IPC

Review socket lifecycle, framing, partial I/O, timeouts, concurrent requests,
stale clients, trust assumptions, shutdown, and terminal fallback.

### D — Swift concurrency and responsiveness

Establish actor ownership, inventory cross-queue mutable state and blocking work,
and assess Swift 6 migration diagnostics.

### E — Hooks and integrations

Review Claude hooks, the Codex wrapper/notifier, notification chaining,
environment handling, subprocess timeouts, voice, cleanup, and terminal support.

### F — Configuration, credentials, and observability

Test missing, partial, malformed, and evolving config; review credentials,
diagnostics, structured logging, privacy, and supportability.

### G — Build, packaging, and distribution

Verify deployment target, compiler policy, signing, install/uninstall behavior,
dependencies, updates, release reproducibility, and Tugboat integration needs.

### H — Maintainability and tests

Propose incremental module boundaries, the smallest high-value automated suite,
and documentation reconciliation.

## Finding format

Each finding includes severity, confidence, evidence, impact, trigger conditions,
recommended remediation, verification, and distribution/Tugboat relevance.

## Deliverables

1. Detailed findings by subsystem.
2. P0–P3 remediation roadmap with dependencies.
3. Test matrix and architectural extraction sequence.
4. Wider-release readiness checklist.
5. Tugboat integration assessment.
