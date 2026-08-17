# Detailed Findings

Severity reflects readiness for a wider user base, not whether the current
single-user installation happens to work today.

## Executive assessment

Agent Monitor is viable and worth productizing. Its core design is appropriately
small and local-first. The release blocker is not missing product functionality;
it is that state, IPC, and subprocess behavior lack enforceable correctness
boundaries. An evolutionary hardening effort is preferable to a rewrite.

## Blockers

### AM-001 — Concurrent session writers corrupt state

**P0 status (2026-08-17): Addressed.** Cross-language per-record locks, unique
same-directory temporary files, `fsync`, atomic rename, and corruption
quarantine now back all lifecycle writers. The 60-event stress regression
passes without malformed JSON or stranded temporary files.

**Confidence:** Confirmed by isolated reproduction.

**Evidence:** `monitor.sh` uses the same `${SESSION_FILE}.tmp` for create and
update paths. Swift also read-modify-replaces the same files from Codex sync and
terminal-target persistence. A 60-event isolated stress run produced 40 failed
updates, malformed final JSON, and a stranded temp file.

**Impact:** Sessions disappear, show stale status, lose prompts/terminal data,
or become permanently unreadable. Failures can also make lifecycle hooks return
nonzero.

**Recommendation:** Introduce one `SessionStore` contract. At minimum, use
unique same-directory temporary files plus an advisory per-session lock and
merge-under-lock. Prefer a small SQLite store or a single local broker process
if multiple languages must remain writers. Add corruption quarantine and
recovery instead of silently skipping malformed files.

**Verification:** Deterministic concurrent transition tests, crash-during-write
tests, and schema migration tests.

### AM-002 — Permission socket protocol has no message framing

**P0 status (2026-08-17): Addressed.** Requests and responses now use bounded
32-bit length-prefixed frames with exact read/write loops and protocol version
1. Accepted clients also receive a 10-second frame-read timeout. Fragmented,
oversized, and incomplete-frame timeout tests cover the core codec.

**Confidence:** High; follows directly from Unix stream semantics.

**Evidence:** `PermissionSocketServer.handleClient` performs one 8 KiB `read`
and immediately decodes it as JSON. The Python hook sends the full serialized
tool input with `sendall`. The response performs one unchecked `write`.

**Impact:** A fragmented or large permission request is rejected by the server,
while the hook can remain blocked for five minutes. This is particularly risky
for large Write/Edit or MCP tool inputs.

**Recommendation:** Use a length-prefixed or newline-delimited protocol with a
maximum message size, read/write loops, explicit protocol version, request ID,
and structured error response. Bound the displayed and transmitted payloads
separately.

**Verification:** Fragment every byte boundary, exceed 8 KiB, send two messages,
disconnect mid-frame, and exercise partial response writes.

### AM-003 — There is no regression suite for safety-critical behavior

**P0 status (2026-08-17): Addressed for the correctness foundation.** SwiftPM
now provides six store/IPC tests and Python provides four hook/integration
tests. Broader installer, config, process, and release tests remain on the
roadmap.

**Confidence:** Confirmed.

**Evidence:** No XCTest target, Swift package tests, shell test harness, or Python
tests are present. Previous reviews rely on manual verification.

**Impact:** Persistence, permission, installer, and lifecycle regressions can be
released without detection. The currently documented TTS-detachment guarantee
has already drifted from the code.

**Recommendation:** Establish tests before structural refactoring. The first
suite should cover `SessionStore`, permission framing, hook state transitions,
Codex notifier installation/chaining, config migration, and process timeout
behavior.

## High severity

### AM-004 — Runtime files expose prompts and tool details to other local users

**P0 status (2026-08-17): Privacy exposure addressed.** Startup and every
writer repair/enforce `0700` session directories and `0600` records. Moving the
runtime directory and adding retention/clear-history controls are deferred to a
compatibility-aware migration.

**Confidence:** Confirmed on the current installation.

**Evidence:** `sessions/` is `0755` and its JSON files are `0644` under the
default `022` umask. Session JSON contains working directories and last prompts;
permission files contain serialized tool input. Only the socket is explicitly
restricted to `0600`.

**Impact:** Other accounts on the Mac can read potentially sensitive prompts,
paths, commands, and tool inputs.

**Recommendation:** Create runtime directories as `0700`, files as `0600`, and
repair permissions on startup/build. Store runtime data under Application
Support rather than inside the source checkout. Document retention and provide
a clear-history action.

### AM-005 — Voice work can delay lifecycle hooks indefinitely

**P0 status (2026-08-17): Hook blocking addressed.** Announcement subprocesses
are fully detached from lifecycle hooks. Network/cache hardening remains P1.

**Confidence:** High.

**Evidence:** The runbook calls full FD detachment “critical,” but current
`announce` call sites invoke it synchronously without redirection/backgrounding.
Background playback children inherit hook descriptors. Live ElevenLabs `curl`
runs synchronously and neither TTS script sets connect or total timeouts.

**Impact:** Claude lifecycle events can stall on network or audio work, making
the agent feel frozen. Cache misses can race while writing the same final MP3.

**Recommendation:** Send announcements to an app-owned queue or fully detached
helper; never perform network work in a lifecycle hook. Add bounded network
timeouts, unique temporary audio files, atomic cache promotion, and per-key
deduplication.

### AM-006 — Terminal resolution and kill operations block the UI thread

**Confidence:** Confirmed statically.

**Evidence:** Row button handlers synchronously run `ps`, `lsof`, WezTerm CLI,
pipe reads, and AppleScript. `killSession` does the same for WezTerm/iTerm2.
Most processes have no timeout.

**Impact:** Clicking a session or its kill control can freeze the entire panel
when a command or scripting bridge is slow.

**Recommendation:** Introduce an async `ProcessRunner` with deadlines,
cancellation, output limits, and typed results. Resolve targets off the main
actor and publish only the final UI action on the main actor.

### AM-007 — Kill UI can hide a still-running process

**Confidence:** Confirmed statically.

**Evidence:** The session file is removed after three seconds regardless of
whether a PID was found, `pkill` launched successfully, or the process exited.
Unsupported terminals therefore get dismissal behavior under a product claim
of “Kill runaway tasks.”

**Impact:** Users can believe a runaway agent was stopped when only its row was
removed.

**Recommendation:** Separate “Stop process” from “Dismiss row,” resolve and
display the target PID, confirm exit, report failure, and offer force-kill as a
second explicit action.

### AM-008 — Config failure is silent and not recoverable in-app

**Confidence:** Confirmed statically.

**Evidence:** Required nested config objects decode all-or-nothing; load errors
are discarded. Save errors are discarded and replacement assumes the destination
exists. External config edits are not watched or reloaded despite documentation
claiming they are picked up. Hook scripts independently parse the same file and
can exit nonzero on malformed JSON.

**Impact:** A small config edit can disable settings, voices, or hooks with no
actionable message. The UI may show defaults while scripts fail differently.

**Recommendation:** Provide tolerant field-level defaults, validation with
human-readable diagnostics, last-known-good recovery, coordinated atomic save,
and a file watcher or explicit reload. Share one versioned schema.

### AM-009 — Release output is host-dependent and not distributable as claimed

**P0 status (2026-08-17): Partially addressed.** Builds now declare macOS 14,
select an explicit architecture/toolchain, and stage output atomically. App
bundling, universal CI artifacts, signing, notarization, and updates remain P2.

**Confidence:** Confirmed for the current artifact.

**Evidence:** `build.sh` sets no deployment target, suppresses compiler warnings,
and produces a bare ad-hoc executable. The inspected binary requires macOS 26,
while the README claims macOS 14+. There is no deterministic CI release build,
app bundle, signing/notarization, update mechanism, or release smoke matrix.

**Impact:** A binary built on a newer Mac may not launch for supported users.
Gatekeeper, Keychain identity, updates, and diagnostics are fragile.

**Recommendation:** Move to a SwiftPM/Xcode app target with an explicit minimum
OS, bundle identifier, signing/notarization, versioning, CI artifacts, and tests
on the supported OS range. Do not suppress warnings in CI.

### AM-010 — Permission cards can be discarded while a hook remains blocked

**P0 status (2026-08-17): Addressed.** Permission records are first-class and
shown even when their lifecycle session is unknown or malformed; scanning no
longer deletes these orphan requests. UI removal is conditional on successful
response delivery, so the file-before-socket registration race remains
retryable.

**Confidence:** High.

**Evidence:** Permission files are filtered to known session IDs and orphan
permission files are deleted during every scan. The permission hook does not
create a session record. If lifecycle tracking was missed, corrupt, or races the
permission event, the socket connection remains pending but no card is shown.

**Impact:** The monitor appears healthy while the agent waits until timeout or
the user returns to the terminal.

**Recommendation:** Make permission requests first-class records independent of
session decode success. Show an “unknown session” card, tie it to a request ID,
and expire it only when the broker connection closes or a deadline is reached.

## Medium severity

### AM-011 — Permission and lifecycle hooks are not fail-soft on bad input

**P0 status (2026-08-17): Addressed for the permission boundary.** The
permission hook validates top-level input, bounds payloads, cleans up, and
fails open without a traceback. Additional lifecycle input normalization can
continue with the schema work.

Malformed or unexpected JSON produces tracebacks/nonzero exits. Validate the
top-level shape, bound fields, log a concise diagnostic, clean up, and exit with
the documented fail-open behavior where appropriate.

### AM-012 — One pending permission per session is an implicit limitation

**P0 status (2026-08-17): Addressed.** Pending clients and files are keyed by a
validated tool-use/request ID, so one session can hold multiple requests.
Expired and disconnected clients are cleaned up independently.

The socket server keys clients by session ID and closes an earlier client when
a second arrives. Key by unique request/tool-use ID and support an ordered queue
per session. This matters more as agents perform parallel tool calls.

### AM-013 — Singleton locking fails open on lock-system errors

If the lock file cannot be opened or `flock` fails for a reason other than an
existing owner, `acquire()` returns true. Multiple processes can then compete
for the socket and runtime state. Fail closed with a visible diagnostic and a
well-defined recovery path.

### AM-014 — Subprocess and discovery work lacks lifecycle control

Periodic discovery can overlap itself, most subprocesses lack deadlines, and
errors are swallowed. Add single-flight guards, timeouts, cancellation on app
termination, output limits, and structured results. Tugboat's existing
`Shell.run(..., timeout:)` is a useful precedent, though it should become a
shared implementation rather than be copied.

### AM-015 — Swift ownership is implicit and blocks Swift 6 migration

Observable/UI types lack explicit `@MainActor` isolation; shared mutable socket
and session state relies on locks/queue comments; cached formatters and singleton
objects are non-Sendable. Define a main-actor UI layer and actor-owned service
state before enabling Swift 6 mode.

### AM-016 — Credentials and network behavior need product-grade boundaries

`.env` files are sourced as shell code rather than parsed as data. Network calls
have inconsistent timeout/status/error behavior. Parse only the required key,
prefer Keychain storage, use ephemeral/bounded URL sessions, and expose privacy
and failure state clearly.

### AM-017 — Observability is too quiet for user support

Many failures use `try?`, empty catches, discarded process status, or no user
feedback. Introduce OSLog categories, redaction rules, a bounded diagnostics
view/export, health indicators for hooks/socket/config, and stable error codes.

### AM-018 — Documentation and behavior have drifted

Examples include 500 ms polling vs. file watching/10-second fallback, 24-hour
vs. 300-second permission timeout, five-second liveness cleanup vs. 30 seconds,
and config reload claims without implementation. Generate or test documented
defaults and timings where possible.

### AM-019 — Install/update/uninstall scope is too invasive for broad release

The build script compiles, copies hooks, mutates Codex config, kills existing
processes by broad name pattern, and launches the app. Installation is tied to
`~/.claude/monitor`. Split build from install, make changes transactional and
reversible, record ownership, support custom app location, and supply a safe
uninstaller/update flow.

## Low severity and polish

### AM-020 — Visual-effect implementation depends on private layer names

Searching for internal `backdrop`, `fill`, and `tone` CALayer names is brittle
across macOS releases. Keep a supported visual fallback and cover appearance
with screenshots on supported OS versions.

### AM-021 — Voice cache keys can collide

Stripping punctuation can map different phrases/projects to the same filename.
Use a content hash plus a readable prefix and include voice/model/settings in
the cache identity.

### AM-022 — Codex log caches need bounded retention

Incremental log reading is a good local optimization, but cursor/path caches are
not pruned and some discovery helpers still read or scan entire rollout trees.
Bound caches to tracked sessions and index logs once by metadata/path.

## Confirmed strengths to preserve

- Local-first operation with no central service requirement.
- Correct current Codex `notify` argv/event model.
- Defensive identifier sanitization around shell/AppleScript boundaries.
- Owner-only Unix socket.
- Event-driven session directory watching with serialized scans.
- Graceful terminal fallback when the monitor is unavailable.
- Incremental rollout parsing in the current local changes.
- Clear skin abstraction and a compact, unobtrusive product experience.
