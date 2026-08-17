# Review Checks

All checks were non-destructive to production behavior. Isolated fixtures used
temporary home directories under `/tmp`.

## Baseline

- Swift source type-check: passed under the current default Swift language mode.
- Shell syntax: `build.sh`, `monitor.sh`, `voice-cache.sh`, and
  `codex-monitor.sh` passed `bash -n`.
- Python syntax: all four Python scripts parsed successfully with `ast.parse`.
- `git diff --check`: passed.
- Automated tests found: none.

Environment observed on 2026-08-17:

- macOS 26.5.2, arm64.
- Apple Swift 6.3.2, default target `arm64-apple-macosx26.0`.
- jq 1.7.1.
- Python 3.14.6.

## Session persistence stress check

Method:

1. Set `HOME` to a new temporary directory.
2. Create one session through `SessionStart`.
3. Launch 60 concurrent `UserPromptSubmit`, `Notification`, and `Stop` hook
   invocations for the same session.
4. Validate exit statuses, resulting JSON, and temporary files.

Result:

- 40 of 60 updates exited nonzero.
- The resulting session file was malformed JSON.
- One shared `.tmp` file remained.
- The malformed file ended with the same extra closing brace observed in an old
  live session file.

This confirms the predictable temp filename/read-modify-replace race.

## Runtime-state validation

- Session JSON files present: 18.
- Malformed session JSON files: 1.
- The malformed file is old (2026-04-29), so its presence demonstrates missing
  recovery but does not establish which historical writer caused it.
- Session directory mode: `0755`.
- Session file mode: `0644`.
- Permission socket mode: `0600`.

## Hook input robustness

`monitor_permission.py` was tested with empty input, malformed JSON, a JSON
array, and a string `tool_input`. All four produced tracebacks and exit code 1.

`monitor.sh` was tested with malformed JSON and a JSON array. Both exited 5 with
jq diagnostics.

## Permission framing review

The Swift server performs one `read` into an 8 KiB buffer and parses that chunk
as a complete JSON document. The Python client sends unbounded serialized
`tool_input`. Unix stream sockets may fragment a send across reads and do not
preserve messages. No delimiter, content length, read loop, or EOF framing is
implemented. The response uses one unchecked `write` as well.

## Codex rollout compatibility

Five recent local rollout logs were inspected by event type only; prompt and
response contents were not read into the report. Current logs contain the three
event types consumed by the monitor:

- `user_message`
- `task_started`
- `task_complete`

The current Codex source still documents top-level `notify` as an argv array and
appends one `agent-turn-complete` JSON argument, matching `codex_notify.py`.

## Build artifact

The existing local binary is arm64, ad-hoc/linker signed, has no app bundle or
bound Info.plist, and declares minimum macOS 26.0. The build script does not set
a deployment target, so the output inherits the build host's default target.

An explicit macOS 14 rebuild could not be completed in this environment because
the selected Command Line Tools compiler and SDK patch versions do not match.
That toolchain issue is separate from the app, but reinforces the need for a
controlled release build environment.

## Swift concurrency

Strict concurrency diagnostics flag shared non-Sendable formatters and
singletons, non-Sendable observable objects captured by dispatch closures,
cross-queue mutable state, and AppKit calls without explicit main-actor
isolation. The standard build suppresses warnings, so these are not visible in
normal development builds.
