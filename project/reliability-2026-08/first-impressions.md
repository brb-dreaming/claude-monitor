# First Impressions

Agent Monitor is a clever, useful app and more thoughtfully engineered than
its “single Swift file plus hooks” shape suggests. It works today, but its
reliability boundaries are mostly protected by convention rather than tests
or enforceable abstractions.

## Strengths

- Pragmatic filesystem-event and Unix-socket architecture with terminal fallback.
- Session scanning is serialized off the main thread.
- Most state writes attempt atomic replacement.
- Session and terminal identifiers are sanitized before sensitive use.
- The permission socket is restricted to the owning user.
- Singleton locking, rediscovery, cleanup, and notification chaining show good
  operational thinking.
- Swift, shell, and Python syntax checks pass.

## Initial concerns

1. **No automated tests.** Permission framing, concurrent updates, notification
   chaining, cleanup, and migration are manually verified.
2. **Monolithic Swift source.** Roughly 4,000 lines own UI, persistence, process
   discovery, networking, credentials, sockets, and terminal control.
3. **Session persistence races.** Predictable `.tmp` paths and independent
   read-modify-replace writers permit lost updates. One older malformed live
   session file demonstrates missing corruption recovery, though not its cause.
4. **Fragile permission framing.** One fixed-size socket read is treated as a
   complete JSON message; partial writes are not handled either.
5. **Concurrency debt.** Strict checking surfaces extensive actor-isolation and
   `Sendable` concerns that obstruct Swift 6 adoption.
6. **Potential UI blocking.** Terminal switching and killing synchronously run
   processes and AppleScript from UI actions.
7. **Deployment target mismatch.** The build does not enforce macOS 14; the
   inspected local binary declares macOS 26 as its minimum version.
8. **Silent failures.** Config, subprocess, socket, and cleanup errors are often
   swallowed.
9. **Documentation drift.** Polling and permission-timeout descriptions disagree
   with the implementation.
10. **Dirty working tree.** Review began with uncommitted Swift and hook changes
    plus an untracked notifier-chain backup; these must be preserved separately.

## Recommended review order

1. Permission and session-state correctness.
2. Concurrency, threading, and UI responsiveness.
3. Test architecture.
4. Process lifecycle and cleanup.
5. Build and deployment compatibility.
6. Error reporting and observability.
7. Modularization and documentation alignment.

The likely path is evolutionary: typed service boundaries, explicit actor/queue
ownership, robust IPC framing, coordinated persistence, structured logging, and
a compact regression suite.
