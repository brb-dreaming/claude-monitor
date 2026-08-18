# Agent Monitor

A floating macOS dashboard that shows live status for your AI agent sessions (Claude Code, Codex), announces completion with voice, surfaces permission prompts for remote approval, and tracks Claude Code usage quotas.

This file is a runbook for AI agents setting this up on behalf of a user. Follow it end to end. Don't skip the hooks step — without it, sessions will never appear in the panel.

---

## Project structure

- `agent_monitor.swift` — SwiftUI app entry point and floating panel
- `Sources/AgentMonitorCore/` — tested persistence and framed-IPC primitives
- `Package.swift` / `Tests/` — Swift and Python regression harnesses
- `build.sh` — compile, sync hooks, create config, launch
- `monitor.sh` — lifecycle hook script for Claude Code (SessionStart/Stop/etc, voice)
- `monitor_permission.py` — permission-granting hook for Claude Code (Unix socket IPC)
- `voice-cache.sh` — ElevenLabs TTS with local MP3 caching
- `codex_notify.py` / `install_codex_notify.py` — Codex `notify` hook installer
- `session_cleanup.py` — periodic cleanup of dead session files
- `session_store.py` — locked, atomic cross-process session persistence
- `config.default.json` — safe default config (tracked in git)
- `config.json` — user's live config (gitignored, created from template on first build)
- `phrases.json` — per-phrase voice tuning template
- `.env.example` — ElevenLabs API key template

---

## Installation runbook

Follow these steps in order. The user has likely just cloned the repo into `~/.claude/monitor` and asked you to set it up.

### Step 1 — Verify install location and dependencies

The repo must live at `~/.claude/monitor`. Paths are hardcoded in `build.sh`, `monitor.sh`, and `agent_monitor.swift` — relocating breaks everything. If it's somewhere else, move it (`mv <current-path> ~/.claude/monitor`) before continuing.

Then confirm dependencies (fix anything missing before moving on):

```bash
test -d ~/.claude/monitor && echo "location ok"
xcode-select -p          # Xcode Command Line Tools
which jq                 # jq (brew install jq)
sw_vers -productVersion  # macOS 14+ (Sonoma)
```

### Step 2 — Ask the user about voice preferences

Before writing any config, walk the user through these choices. Present the options, recommend a default, and ask.

**Voice provider (`tts_provider`)**

1. **`say`** *(default, recommended for first-time setup)* — macOS built-in speech. Zero setup, works immediately. Good quality with Premium voices (Zoe, Ava, Tom).
2. **`cache`** *(recommended upgrade)* — ElevenLabs AI voices with smart caching. Each phrase generated once, saved as MP3, replayed instantly (~10ms). Requires an ElevenLabs API key (free tier works).
3. **`elevenlabs`** — fresh ElevenLabs call every announcement. Adds 1–3s latency. Useful only while tuning voice settings.

**Announcement events (`announce.*`)**

- `on_done` *(default: on)* — "project-name done" when an agent finishes
- `on_attention` *(default: on)* — "project-name needs attention" when permission is needed
- `on_start` *(default: off)* — "project-name starting" when a session begins
- `volume` *(default: 0.5)* — 0.0 to 1.0

**Usage tracking (`usage.enabled`, default: off)**

Ask whether they want to see their Claude Code quota (session 5h + weekly 7d) in the panel. This reads OAuth credentials from macOS Keychain — a one-time Keychain prompt will appear the first time the panel opens. They should click "Always Allow."

### Step 3 — Build

```bash
~/.claude/monitor/build.sh
```

This compiles the Swift app, syncs hook scripts into `~/.claude/hooks/`, installs the Codex `notify` hook into `~/.codex/config.toml`, copies `config.default.json` to `config.json` if missing, and launches the panel.

### Step 4 — Write config.json with the user's choices

After `build.sh` creates `config.json` from the defaults, edit it to reflect their answers from Step 2. Use the Edit tool — don't rewrite the whole file. For example, if they chose `cache` provider and want `on_start` on:

```json
{
  "tts_provider": "cache",
  "announce": { "on_start": true, ... }
}
```

### Step 5 — Install Claude Code hooks (critical — do not skip)

If the user uses Claude Code, add six hook entries to `~/.claude/settings.json`. **Merge** these into any existing `"hooks"` block — don't overwrite it.

```json
{
  "hooks": {
    "SessionStart": [
      { "hooks": [{ "type": "command", "command": "$HOME/.claude/hooks/monitor.sh SessionStart" }] }
    ],
    "UserPromptSubmit": [
      { "hooks": [{ "type": "command", "command": "$HOME/.claude/hooks/monitor.sh UserPromptSubmit" }] }
    ],
    "Stop": [
      { "hooks": [{ "type": "command", "command": "$HOME/.claude/hooks/monitor.sh Stop" }] }
    ],
    "Notification": [
      {
        "matcher": "permission_prompt",
        "hooks": [{ "type": "command", "command": "$HOME/.claude/hooks/monitor.sh Notification" }]
      }
    ],
    "PermissionRequest": [
      {
        "hooks": [
          { "type": "command", "command": "python3 $HOME/.claude/hooks/monitor_permission.py", "timeout": 300 }
        ]
      }
    ],
    "SessionEnd": [
      { "hooks": [{ "type": "command", "command": "$HOME/.claude/hooks/monitor.sh SessionEnd" }] }
    ]
  }
}
```

Read the current `settings.json` first, merge carefully, and write it back. If the user prefers, the `update-config` skill (when available) can do the merge safely.

Codex doesn't need any settings changes — `build.sh` already wired its notify hook.

### Step 6 — ElevenLabs setup (only if they chose `cache` or `elevenlabs`)

1. Copy the env template and ask the user to paste their API key:

   ```bash
   cp ~/.claude/monitor/.env.example ~/.env
   ```

   Then guide them to edit `~/.env` and replace `sk_your_api_key_here` with a real key. (`~/.env` is the default location referenced by `config.json`'s `elevenlabs.env_file` field. A different path works if the user prefers — update `env_file` to match.)

2. Ask whether they have a specific ElevenLabs voice they want to use. If yes, they can either paste the `voice_id` into the settings popover's **Paste voice ID** field, or you can set `elevenlabs.voice_id` in `config.json` directly. If they don't have one in mind, the settings panel has a voice picker that lists their available voices once the API key is set.

### Step 7 — Verify

Walk through this with the user:

1. The floating panel should be visible in the top-right of the screen.
2. Open a terminal and start a new agent session (e.g., run `claude` or `codex`).
3. The session should appear in the panel with status *starting*.
4. Send a prompt — status flips to *working* with a preview.
5. Let it finish — status flips to *done* and (if voice is on) they hear the announcement.
6. Click the session row — the terminal jumps to that tab.

If sessions don't appear in Claude Code: double-check Step 5 merged into `~/.claude/settings.json` correctly. If voice doesn't play: check `announce.enabled` is true and volume > 0 in the settings popover.

---

## Maintenance notes (for future edits to the codebase)

### Build & relaunch

```bash
~/.claude/monitor/build.sh
```

Kill + restart:

```bash
pkill agent_monitor; sleep 1; ~/.claude/monitor/build.sh
```

### Skins

Four built-in skins registered at `agent_monitor.swift:247` (`allSkins: [glass, obsidian, terminal, teletype]`):

1. **Glass** *(default)* — frosted glass with configurable `blur`, `opacity`, `tintR/G/B`, `tintStrength` via the `glass` config key. Uses `NSVisualEffectView` with private CALayer manipulation to decouple blur from opacity. 16px corner radius.
2. **Obsidian** — dark neumorphic. Solid dark gradient, top-edge highlight fading along the sides, deep shadow. Depth from shadows, not strokes. 16px corner radius.
3. **Terminal** — retro phosphor green CRT. Monospaced throughout, near-black background with green tint. 6px corner radius.
4. **Teletype** — warm cream paper with ink-ribbon accents. Opaque with subtle texture.

### Hook detachment (critical)

All `announce` calls in `monitor.sh` MUST fully detach from the hook process:

```bash
announce "message" </dev/null >/dev/null 2>&1 &
disown 2>/dev/null
```

Claude Code waits for inherited file descriptors to close before considering a hook complete. Without FD redirection, backgrounded TTS (especially live ElevenLabs API calls) blocks the hook for the duration of the network request.

### Permission IPC architecture

`monitor_permission.py` is launched by Claude Code's `PermissionRequest` hook.
It atomically writes a private
`{session_id}.{request_id}.permission` record, connects to the owner-only Unix
socket at `~/.claude/monitor/monitor.sock`, and exchanges protocol-v1 JSON in
bounded 4-byte length-prefixed frames. Accepted clients have a 10-second frame
read timeout; registered requests have bounded deadlines. Multiple permission
requests can be pending for one session. The UI removes a card only after its
response frame is delivered, so a click that races socket registration remains
available for retry. IPC failure exits cleanly and leaves Claude Code's terminal
dialog as the fallback. The hook timeout is 300 seconds (5 minutes), matching
`TIMEOUT_SECONDS`.

### Session file watching

The Swift app watches `~/.claude/monitor/sessions/` using
`DispatchSourceFileSystemObject` events (not interval polling). All hook and app
writers use the same per-record lock convention, unique same-directory temporary
files, `fsync`, and atomic rename. Runtime directories are `0700` and records
are `0600`; existing modes are repaired. Malformed records are quarantined as
hidden `*.corrupt.*` files instead of being silently ignored forever.

### Reliability checks

Run these before publishing persistence, hook, or permission changes:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --disable-sandbox
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s Tests -p 'test_*.py' -v
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc -typecheck \
  agent_monitor.swift Sources/AgentMonitorCore/*.swift \
  -framework Cocoa -framework SwiftUI -framework Combine -framework Security \
  -parse-as-library -target arm64-apple-macosx14.0
```

The Swift tests cover concurrent persistence, corruption recovery, private file
modes, fragmented frames, oversized frames, and incomplete-frame timeouts. The
Python suite covers concurrent hook events and permission-hook fallback/IPC.

### Defaults

`config.default.json` ships with `tts_provider: "say"`, `skin: "glass"`, `usage.enabled: false`. New users get working voice with zero external setup; the `cache` provider is the recommended upgrade path once they have an ElevenLabs key.
