# P0 Standalone-App Implementation

Completed on 2026-08-17 against the starting state recorded in
`p0-baseline.md`. Existing user changes were preserved and no commit was made.

## Outcome

The standalone app's two most failure-prone boundaries—shared session state and
permission IPC—now have explicit, tested correctness contracts. Runtime records
are owner-private, malformed records recover without poisoning the UI, hook
audio no longer holds lifecycle descriptors, and builds no longer replace the
working executable until compilation succeeds.

## Implemented

### Transactional session persistence

- Added Swift and Python session-store implementations using the same
  `.locks/<record>.lock` convention.
- Writes merge under an advisory cross-process lock, use unique temporary files
  in the destination directory, call `fsync`, and finish with atomic rename.
- Hook events, Codex lifecycle events, discovery, terminal-target persistence,
  cleanup, pruning, and kill-row deletion now use transactional semantics.
- Malformed JSON is moved aside as `*.corrupt.<uuid>` and a clean record can be
  created; malformed records are no longer silently permanent.
- Codex notification handling has one lifecycle writer instead of two competing
  read-modify-write paths.

### Permission broker protocol

- Added protocol version 1 with a 4-byte big-endian length prefix and a 1 MiB
  maximum frame.
- Both sides perform exact, interruption-safe read/write loops.
- Accepted sockets receive a bounded 10-second read timeout before frame
  parsing, preventing silent or partial clients from retaining workers and file
  descriptors indefinitely.
- Every request has a unique request/tool-use ID and session ID; pending clients
  are keyed by request, allowing parallel prompts in one session.
- Permission files use `<session>.<request>.permission`, are atomically written,
  and are removed individually.
- Unknown-session requests remain visible in the panel instead of being deleted.
- Request payload and display sizes are bounded. Malformed input and unavailable
  IPC fail open to the terminal without traceback.
- Pending sockets have bounded deadlines and stale clients are closed by a timer
  running independently from the blocking accept loop.
- Permission cards are removed only after the matching response frame is
  successfully delivered to its registered socket. An early click during the
  file/socket registration race leaves the card available for retry.
- Socket-path ownership is explicit: a second instance that loses the singleton
  lock cannot unlink the active instance's broker socket while terminating.

### Privacy and operational hardening

- Session directories are `0700`; session and permission files are `0600`.
- Existing live modes are repaired at app startup and by writer paths.
- Lifecycle announcements are detached with standard descriptors redirected.
- Build output is staged and atomically promoted only after a successful build.
- The build selects full Xcode when available, declares macOS 14 as the default
  minimum, validates architecture/optimization inputs, and installs the shared
  Python store helper with the hooks.

### Test seam

- Added a SwiftPM `AgentMonitorCore` target without changing the shipping
  executable entry point.
- Added store tests for 100 concurrent updates, corruption recovery/quarantine,
  and owner-only modes.
- Added IPC tests for byte-at-a-time fragmentation of a 12 KiB frame, early
  oversized-frame rejection, and timeout of an incomplete frame.
- Added Python integration tests for 60 concurrent hook events, corrupt-record
  recovery, malformed permission input, private files, and fragmented socket
  responses.

## Verification

All checks passed on the implementation:

- Swift: 7 tests, 0 failures.
- Python/integration: 4 tests, 0 failures.
- Full `agent_monitor.swift` plus core sources typecheck for
  `arm64-apple-macosx14.0`: passed.
- Shell syntax and all edited Python files: passed.
- Live state repair: session directory and records are owner-only; the existing
  malformed session was quarantined.
- Installed executable: explicit minimum macOS 14.0.

The local Command Line Tools selection has a compiler/SDK patch mismatch, so
verification uses the installed full Xcode toolchain. This is a workstation
configuration issue; the release pipeline should pin its toolchain.

## Deliberate P0 boundaries

- Runtime state remains at `~/.claude/monitor/sessions` to preserve compatibility
  with installed hooks. Moving it to Application Support needs a versioned,
  reversible migration and custom-location support.
- Retention limits and a Clear History control require product/UI decisions and
  remain open.
- The store persists compatible JSON dictionaries rather than forcing a schema
  migration in the same change. Versioned record models remain advisable.
- Build/install are safer but still coupled. A signed app bundle, CI artifacts,
  transactional installer/uninstaller, and updater remain release work.
- P1 still owns bounded subprocess execution, truthful stop/dismiss behavior,
  config recovery, deeper voice/network hardening, and support diagnostics.

## Files introduced

- `Package.swift`
- `Sources/AgentMonitorCore/SessionFileStore.swift`
- `Sources/AgentMonitorCore/IPCFrame.swift`
- `Tests/AgentMonitorCoreTests/SessionFileStoreTests.swift`
- `Tests/AgentMonitorCoreTests/IPCFrameTests.swift`
- `session_store.py`
- `tests/test_p0.py`
