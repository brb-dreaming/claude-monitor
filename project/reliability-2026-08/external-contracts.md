# External Integration Contracts

Checked on 2026-08-17. These links are intentionally recorded because Claude
Code and Codex integration behavior can change independently of Agent Monitor.

## Claude Code

- [Hooks reference](https://code.claude.com/docs/en/hooks)
- [Hooks guide](https://code.claude.com/docs/en/hooks-guide)

Current relevant behavior:

- `PermissionRequest` receives tool/session data on stdin.
- A command hook may return
  `hookSpecificOutput.decision.behavior` as `allow` or `deny`.
- Command-hook timeout defaults to 600 seconds; Agent Monitor explicitly uses
  300 seconds.
- Multiple matching hooks run in parallel.
- Permission outputs can now carry `updatedInput` and `updatedPermissions`.

Agent Monitor's basic allow/deny JSON remains compatible. Request identity,
framing, timeout behavior, and richer permission updates are internal monitor
concerns and opportunities.

## Codex

- [Current config source and `notify` contract](https://github.com/openai/codex/blob/main/codex-rs/core/src/config/mod.rs)
- [Codex configuration docs](https://github.com/openai/codex/blob/main/docs/config.md)

Current relevant behavior:

- `notify` is a top-level argv array.
- Codex appends one JSON event argument to the configured command.
- The completion event type remains `agent-turn-complete`.

This matches the monitor installer and `codex_notify.py`. Recent local rollout
logs also retain the `user_message`, `task_started`, and `task_complete` payload
types used by the current log synchronizer.

## Contract-test recommendation

Keep local fixtures for the accepted event schemas and review these upstream
links during releases. External documentation should inform compatibility tests,
not be fetched dynamically by the app.
