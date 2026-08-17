# Reliability Roadmap

The roadmap is ordered to reduce risk early and avoid refactoring unstable
behavior. “P0” means required before actively growing distribution.

## P0 — Correctness foundation

**Status (2026-08-17): substantially complete for the standalone app.** The
implemented scope and verification evidence are in `p0-implementation.md`.
Application Support migration, retention UI, full versioned data models, and
release CI remain deliberately staged work rather than risky in-place changes.

### 0. Preserve the starting point

- Review and checkpoint the pre-existing dirty changes separately.
- Remove or archive the notifier-loop backup intentionally.
- Record a reproducible baseline build and smoke test.

### 1. Establish the test harness

- Create a SwiftPM workspace with `AgentMonitorCore` and test targets while the
  existing executable remains the shipping entry point.
- Add Python tests for notifier install/chaining and permission-hook validation.
- Add shell lifecycle tests using an isolated `HOME` and fake binaries.
- Make persistence and IPC stress checks mandatory in CI.

### 2. Replace ad hoc session writes

- Define versioned `SessionRecord`, `PermissionRecord`, and transition types.
- Introduce a single `SessionStore` API with locking/transactions.
- Add unique atomic temp files, strict file modes, corruption quarantine, and
  last-known-good recovery.
- Route hook, Codex sync, discovery, target persistence, and cleanup through the
  same semantics.

### 3. Build a real permission broker protocol

- Length-prefix frames and cap payload size.
- Add protocol version, request ID/tool-use ID, session ID, deadline, and errors.
- Support multiple outstanding requests and unknown/missing sessions.
- Handle partial reads/writes, disconnects, shutdown, and timeout explicitly.
- Preserve fail-open terminal fallback.

### 4. Lock down runtime privacy

- Move state to `~/Library/Application Support/AgentMonitor`.
- Enforce `0700` directories and `0600` files; repair existing installs.
- Add retention limits and “Clear history.”
- Redact diagnostics by default.

## P1 — Responsiveness and operational reliability

**Status (2026-08-17): in progress.** The first subprocess/responsiveness slice
is recorded in `p1-implementation.md`.

### 5. Centralize subprocess execution

- [x] Add `ProcessRunner` with timeout, output cap, exit status, typed launch
  errors, and TERM→KILL escalation.
- [x] Move terminal resolution and stop work off the main thread.
- [x] Add single-flight discovery.
- [ ] Add explicit cancellation handles and terminate all children at shutdown.
- [ ] Add timeout isolation for AppleScript terminal bridges.

### 6. Make notifications non-blocking

- Queue TTS in the app or a dedicated detached helper.
- Add network deadlines and retries appropriate to user-triggered audio.
- Generate cache files atomically with per-key deduplication.
- Treat audio as best-effort without holding lifecycle-hook descriptors.

### 7. Make configuration resilient

- Version the schema and default each field independently.
- Validate ranges/enums and show actionable errors.
- Save transactionally; recover last-known-good config.
- Watch for external changes or offer explicit reload.
- Move API keys to Keychain and parse legacy `.env` as data only.

### 8. Make destructive controls truthful

- Separate Stop and Dismiss.
- Resolve the exact target and show it.
- Verify termination and report failure; expose force-kill only as escalation.

### 9. Add support-grade observability

- OSLog categories for app, store, IPC, hooks, discovery, terminal, usage, voice.
- Health checks for hooks, socket, config, dependencies, and permissions.
- Redacted diagnostic export with app/version/environment identifiers.

## P2 — Productization and maintainability

### 10. Extract explicit modules

Suggested boundaries:

```text
AgentMonitorCore
  Models
  SessionStore
  PermissionBroker
  ProcessRunner
  ConfigStore
  Diagnostics

AgentMonitorIntegrations
  ClaudeHooks
  CodexNotifier
  Terminal.app
  iTerm2
  WezTerm
  Voice

AgentMonitorUI
  Panel
  SessionList
  PermissionCards
  Settings

AgentMonitorApp
  lifecycle and dependency composition only
```

This is an extraction sequence, not a rewrite. Move tested behavior one seam at
a time.

### 11. Adopt explicit Swift concurrency

- Mark UI/config-observable types `@MainActor`.
- Use actors for store/broker/process coordination.
- Remove unsafely shared formatters and mutable singleton state.
- Enable strict concurrency warnings in CI, then migrate to Swift 6 mode.

### 12. Create a real release pipeline

- App bundle, stable bundle ID, explicit macOS minimum, semantic version.
- Signed/notarized universal artifacts from controlled CI.
- Install/update/uninstall flows independent from compilation.
- Smoke tests on oldest and newest supported macOS versions.
- Do not suppress warnings in CI.

### 13. Reconcile documentation

- Generate config examples from the schema/defaults.
- Test hook snippets and timeout values.
- Document privacy, data retention, compatibility, diagnostics, and recovery.

## P3 — Tugboat integration

Do not paste the current 4,000-line monitor into Tugboat's 2,480-line single-file
app. Extract the core first, then choose one of two product shapes:

### Recommended: shared core, one optional Tugboat feature

- Tugboat and standalone Agent Monitor import `AgentMonitorCore` and integrations.
- Tugboat owns app lifecycle and can open the monitor panel as an opt-in module.
- Standalone Agent Monitor remains available for users who do not want Tugboat.
- Use one installer/health system so hooks have a single owner.

### Alternative: companion process

- Tugboat launches a signed Agent Monitor helper and communicates through the
  versioned broker protocol.
- Better fault isolation, but more release/update complexity.

The shared-core option is the better default because both apps already solve
similar macOS concerns—process execution, floating panels, local caches, and
diagnostics. Tugboat's timeout-aware process runner is a useful design input.

### Integration gates

- No hardcoded `~/.claude/monitor` runtime dependency.
- One source of truth for install/uninstall and hook ownership.
- Feature can be disabled without affecting Tugboat's port-monitoring role.
- Permission UI remains visually prominent and never hidden behind a menu.
- Separate privacy controls for agent prompts/tool inputs.
- Independent crash/failure telemetry or diagnostics boundaries.

## Release readiness checklist

- [x] Persistence stress tests pass with zero corrupt updates.
- [x] Permission protocol framing and fragmentation tests pass; request IDs
  permit concurrent requests.
- [ ] Runtime files are private; retention controls remain to be implemented.
- [x] No lifecycle hook waits on network/audio work.
- [ ] UI actions have bounded execution and visible failure states.
- [ ] Config corruption is recoverable without terminal intervention.
- [ ] Stop vs. dismiss semantics are truthful.
- [ ] Signed release runs on the oldest supported macOS version.
- [ ] Install/update/uninstall are transactional and reversible.
- [ ] Diagnostics are useful and redact prompts/secrets.
- [ ] Claude and Codex contract tests match current official behavior.
- [ ] Documentation timings/defaults are generated or tested.
