# Troubleshooting

## Sessions don't appear

Sessions are created when Claude Code hooks fire. If a session was started before the hooks were configured, it won't appear until its next event (sending a prompt, finishing, or hitting a permission prompt).

**Fix:** Send a new prompt in the session, or restart it. You can also click the gear icon and hit "Refresh sessions" to scan for running Claude processes.

## Some sessions show "Projects" as the name

The project name comes from the directory where you started Claude Code (`basename $CWD`). If you started Claude Code from `/Users/you/Projects/`, it'll show "Projects" instead of a specific project name.

**Fix:** Start Claude Code from inside the project directory:
```bash
cd ~/Projects/my-project && claude
```

## Click doesn't switch terminal tabs

The monitor matches terminal tabs by TTY device path. Check the session's JSON file in `~/.claude/monitor/sessions/`:

```bash
cat ~/.claude/monitor/sessions/*.json | jq '{project, terminal, terminal_session_id}'
```

If `terminal_session_id` is empty, the hook couldn't detect the terminal. Send another prompt in that session to backfill it.

**Why it might be empty:** The hook detects the TTY by walking the process tree (`ps -o ppid=`). If the process tree is unusually deep or the parent shell doesn't have a TTY (rare), detection fails gracefully.

## No voice announcements

Check these in order:

1. **Master toggle** — is `announce.enabled` set to `true` in `config.json`? Also check the toggle in the settings popover (gear icon).

2. **Volume** — is `announce.volume` above `0.0`?

3. **Provider** — if using ElevenLabs:
   - Is `tts_provider` set to `"elevenlabs"`?
   - Does the `.env` file exist at the path specified in `elevenlabs.env_file`?
   - Does it contain a valid `ELEVENLABS_API_KEY`?
   - Is the `voice_id` valid?

4. **Test manually:**
   ```bash
   echo '{"session_id":"test","cwd":"/tmp"}' | ~/.claude/hooks/monitor.sh Stop
   ```
   You should hear "tmp done" (or see an error).

5. **ElevenLabs fallback** — if the ElevenLabs API call fails (bad key, network issue), the hook automatically falls back to macOS `say`. If you hear your macOS voice instead of your ElevenLabs voice, check your API key.

## Voice picker shows no voices

The settings popover fetches voices from ElevenLabs on app launch. It only shows your **library** voices (cloned, generated, professional) — not premade ones.

If the list is empty:
- Verify your `.env` file path and API key
- Make sure you have at least one voice in your ElevenLabs voice library
- Any voices you've saved (via Generate, Paste, or library selection) appear in the `voices` array in config.json — they show up even without an API connection

## Panel doesn't appear after build

Check if it's running:
```bash
pgrep -l agent_monitor
```

Gracefully stop and rebuild:
```bash
pkill agent_monitor && ~/.claude/monitor/build.sh
```

If compilation fails, make sure Xcode Command Line Tools are installed:
```bash
xcode-select --install
```

## Panel is in the wrong position

Reset the saved position:
```bash
defaults delete agent_monitor monitorX
defaults delete agent_monitor monitorY
pkill agent_monitor && ~/.claude/monitor/build.sh
```

It will reappear in the top-right corner.

## Sessions stay after Claude Code exits

Normally, the `SessionEnd` hook removes the session file after 5 seconds. If sessions persist:

- The terminal tab might still be open (the liveness check only prunes when the TTY is gone)
- The `SessionEnd` hook might not have fired (crash, SIGKILL)

**Fix:** Close the terminal tab (the liveness check will clean it up within 5 seconds), or click the X button on the session row.

## Build warnings

The Swift compiler may show deprecation warnings. These are cosmetic and don't affect functionality. Common ones:

- `launchApplication` deprecation — the code uses the modern `openApplication(at:configuration:)` API
- `onChange(of:perform:)` — may appear on newer macOS versions

## Permission buttons don't appear

The Allow/Deny buttons require the `PermissionRequest` hook to be configured in `~/.claude/settings.json` with the Python script:

```json
"PermissionRequest": [
  {
    "hooks": [
      {
        "type": "command",
        "command": "python3 $HOME/.claude/hooks/monitor_permission.py",
        "timeout": 300
      }
    ]
  }
]
```

Also verify `monitor_permission.py` exists at `~/.claude/hooks/monitor_permission.py`.

## Permission buttons appear but clicking Allow doesn't work

The monitor app communicates with the Python hook via a Unix socket at `~/.claude/monitor/monitor.sock`. Check:

1. **Socket exists** — `ls -la ~/.claude/monitor/monitor.sock` (created when the monitor app launches)
2. **Monitor app is running** — `pgrep -l agent_monitor`
3. **Check ownership** — the socket should appear as `srw-------` (`0600`)
4. **Restart the app** — `pkill agent_monitor && ~/.claude/monitor/build.sh`

If a permission card appears just before its socket finishes registering, an
early click intentionally leaves the card visible. Retry the same action once.

If the socket doesn't exist, the monitor app failed to start its socket server. Check Console.app for `[AgentMonitor]` log messages.

## Permission falls through to terminal dialog

This can happen if the Python hook can't connect to the socket (monitor app not running) or if the connection times out. The hook is designed to fall through gracefully — Claude Code shows its standard terminal dialog as a fallback.

## Hook adds latency to Claude Code

Each hook invocation adds ~10ms of overhead (mostly from the `ps` process tree walk for TTY detection). This is imperceptible in normal use. The TTS call runs in the background and doesn't block. The permission hook adds no latency — it blocks independently on the socket.

## Usage shows "No credentials"

The usage feature needs an OAuth token from Claude Code. Check:

1. **Are you logged in?** Run `claude login` if you haven't authenticated, or if your session expired.

2. **Where are credentials stored?** The app checks two places:
   - `~/.claude/.credentials.json` (file-based, some installs)
   - macOS Keychain, service `Claude Code-credentials` (most installs)

3. **Verify Keychain entry exists:**
   ```bash
   security find-generic-password -s "Claude Code-credentials" 2>/dev/null && echo "Found" || echo "Not found"
   ```

4. **Check the token structure** — the app expects `claudeAiOauth.accessToken` inside the Keychain blob:
   ```bash
   security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print('Has token:', 'accessToken' in d.get('claudeAiOauth', {}))"
   ```

## Usage shows "Auth expired"

The OAuth token has expired. The app clears its cached token and will retry on the next poll.

**Fix:** Run `claude login` to re-authenticate, then click the refresh button in the usage popover.

## Usage shows "Rate limited — backing off to Xm"

The Anthropic API returned HTTP 429. This is normal if you've been opening the usage popover frequently or if multiple tools are polling the same endpoint.

**What happens:** The poll interval doubles automatically (5min → 10min → 15min cap). Once a successful response comes back, it resets to 5 minutes. No action needed — just wait.

## Usage shows "HTTP 403" or "HTTP 500"

- **403** — Your OAuth token may lack the `user:profile` scope. Re-authenticate with `claude login`.
- **500** — Anthropic API issue. The app will retry on the next poll interval.

## macOS Keychain keeps prompting for access

When `agent_monitor` first reads your Claude Code credentials from the Keychain, macOS shows a permission dialog. Click **Always Allow** to grant permanent access.

If you accidentally clicked "Deny":

1. Open **Keychain Access.app**
2. Search for "Claude Code-credentials"
3. Double-click the entry → **Access Control** tab
4. Add `agent_monitor` to the allowed applications list (or click "Allow All Applications")
5. Save changes

The app caches the token in memory after the first successful read, so the Keychain is only accessed when:
- The app first launches
- The cached token is about to expire (within 60 seconds of `expiresAt`)
- A 401 response clears the cache

## Panel won't collapse / expand

The chevron toggle (▶/▼) next to "Claude" in the header collapses and expands the session list. If it seems stuck:

1. Check if the state is persisted incorrectly:
   ```bash
   defaults read agent_monitor monitorExpanded
   ```
2. Reset it:
   ```bash
   defaults delete agent_monitor monitorExpanded
   pkill agent_monitor && ~/.claude/monitor/build.sh
   ```
