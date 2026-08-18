# P1 Standalone-App Implementation

Started on 2026-08-17 on `agent/p0-reliability-hardening` after P0 publication.

## Slice 1 — Bounded subprocesses and responsive terminal actions

### Implemented

- Added `AgentMonitorCore.ProcessRunner` with:
  - configurable hard deadlines;
  - independent capped stdout/stderr capture that continues draining after the
    cap is reached;
  - termination status and timeout/truncation metadata;
  - typed launch failure;
  - graceful termination followed by bounded `SIGKILL` escalation;
  - dedicated concurrent stdout/stderr readers with exact trailing-output
    capture;
  - parent-side write-descriptor closure and a bounded drain fallback when
    descendants inherit pipe descriptors.
- Migrated every direct `Process` call in `agent_monitor.swift`, including `ps`,
  `lsof`, `pkill`, and WezTerm CLI operations.
- Removed shell/awk interpolation from migrated process discovery and stop
  paths; arguments are passed directly after validation.
- Moved row-click live-target resolution and stop work off the main thread.
- Made periodic/manual session discovery single-flight.

### Tests

- Captures stdout, stderr, and nonzero termination status.
- Terminates a command at its deadline.
- Caps captured output while continuing to drain the child pipe.
- Captures large simultaneous stdout/stderr streams exactly.
- Escalates when a process ignores `SIGTERM`.
- Returns promptly when a descendant retains inherited pipe descriptors.

The Swift suite now contains 13 passing tests. The ProcessRunner subset also
passes 10 consecutive stress repetitions. The complete app typechecks for
the macOS 14 target, and `agent_monitor.swift` contains no direct `Process`
construction or unbounded pipe reads.

### Remaining in this area

- Model active commands with cancellation handles and cancel them during app
  shutdown.
- Bound `NSAppleScript` terminal operations; they do not use `ProcessRunner`.
- Add user-visible progress/failure states for terminal switching and stopping.
- Address AM-007 by separating Stop from Dismiss and verifying process exit
  before changing the row state.
