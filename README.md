<div align="center">

# Agent Monitor

**Command your AI agents from one floating panel.**

Grant permissions without switching windows. Hear when an agent finishes or needs you. Track your usage quota. Click to jump to any session. Stop supported agent processes. All from a tiny always-on-top dashboard you can drag anywhere.

<br>

<img src="assets/demo.gif" width="380" alt="Agent Monitor demo" />

<br>
<br>

</div>

---

<div align="center">
<table>
<tr>
<td><img src="assets/Monitor.png" width="280" alt="Session list" /></td>
<td><img src="assets/Monitor Menu.png" width="280" alt="Settings popover" /></td>
</tr>
<tr>
<td align="center"><sub>Live session tracking</sub></td>
<td align="center"><sub>Voice & skin settings</sub></td>
</tr>
</table>
</div>

## What it does

**Hear your agents.** A voice announces when a session finishes or needs your attention, so you can click away from the terminal and come back only when there's something to do.

**Approve without switching.** Permission prompts surface right on the panel — Allow, Deny, or jump to the terminal — so you don't lose flow hunting for the right window.

**See everything at a glance.** Every running agent shows up with its directory name, live status, last prompt, and elapsed time. Click a row to jump straight to that terminal tab.

**Know your quota.** Optional session (5-hour) and weekly quota bars, colored green / yellow / red so you can pace yourself before you hit a wall.

**Stay out of the way.** No dock icon. Floats on all Spaces. Drag it anywhere. Collapse it to a thin header when you want it even smaller.

Works with **Claude Code** and **Codex**. Sessions from both agents show up automatically, tagged with a small badge so you know which is which.

## Requirements

- **macOS 14+** (Sonoma or later)
- **[Claude Code](https://docs.anthropic.com/en/docs/claude-code)** and/or **[Codex](https://github.com/openai/codex)** installed
- **Xcode Command Line Tools** — `xcode-select --install`
- **jq** — `brew install jq`
- *(Optional)* An [ElevenLabs](https://elevenlabs.io) API key if you want AI voices

### Terminal compatibility

Session tracking, voice, and permission granting work in **every terminal**. Click-to-switch (jumping to the right tab when you click a row) depends on how scriptable the terminal is:

| Terminal                        | Click-to-switch | Kill session |
| ------------------------------- | :-------------: | :----------: |
| Terminal.app                    |        ✓        |      ✓       |
| iTerm2                          |        ✓        |      ✓       |
| WezTerm                         |        ✓        |      ✓       |
| Ghostty, Warp, kitty, Alacritty |        ?        |      —       |
| VS Code / Cursor terminal       |        —        |      —       |

Sessions from unsupported terminals still appear in the panel with live status and voice — you just won't be able to jump back to them with a click.

## Install

### The easy way — let your agent do it

Clone the repo to `~/.claude/monitor` (this path is required — the app looks for its config, sessions, and socket there):

```bash
git clone https://github.com/brb-dreaming/agent-monitor.git ~/.claude/monitor
```

Then paste this into whichever agent you use (Claude Code, Codex, Cursor — any agent with filesystem access works):

> Set up Agent Monitor. Read `~/.claude/monitor/CLAUDE.md` and follow it end to end. Ask me about voice and announcement preferences before you build.

Your agent will check dependencies, ask you a few questions about voice and announcements, build the app, wire up the hooks, and confirm everything works.

### The manual way

<details>
<summary>Click to expand step-by-step instructions</summary>

<br>

**1. Install dependencies**

```bash
xcode-select --install
brew install jq
```

**2. Clone and build**

```bash
git clone https://github.com/brb-dreaming/agent-monitor.git ~/.claude/monitor
~/.claude/monitor/build.sh
```

`build.sh` compiles the app, syncs hook scripts into `~/.claude/hooks/`, wires the Codex notify hook into `~/.codex/config.toml`, creates `config.json` from the defaults, and launches the panel.

**3. Add Claude Code hooks**

Merge the entries below into `~/.claude/settings.json` (don't replace an existing `"hooks"` block — add these entries alongside anything you already have):

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

Codex doesn't need any settings changes — `build.sh` handles that for you.

**4. Launch**

```bash
~/.claude/monitor/build.sh
```

The panel appears in the top-right corner. Drag it anywhere — it'll stay put.

</details>

### Verify it's working

1. Open the panel — any already-running sessions appear automatically.
2. Start a new agent session in a terminal — it shows up as *starting*.
3. Send a prompt — status changes to *working* with a preview of what you asked.
4. Let it finish — status flips to *done* and you hear the announcement.
5. Click the row — your terminal jumps to that tab.

## Voice

Voice announcements work out of the box using macOS built-in speech. No setup needed.

If you want AI-quality voice, add an [ElevenLabs](https://elevenlabs.io) API key and switch providers:

| Provider                        | Quality | Setup          | Latency                    |
| ------------------------------- | ------- | -------------- | -------------------------- |
| `say` *(default)*               | Good    | None           | Instant                    |
| `cache` *(recommended upgrade)* | Best    | ElevenLabs key | ~10ms (plays cached audio) |
| `elevenlabs`                    | Best    | ElevenLabs key | 1–3s (live API call)       |

**Start with `say`.** It's great. If you want to upgrade later, `cache` is the sweet spot — the first time a phrase is spoken ("my-project done"), it calls ElevenLabs and saves an MP3 to disk. Every future time, it plays back instantly. Since announcements follow predictable patterns, you'll hit the API a handful of times on day one and never again.

Full setup and phrase tuning: [docs/VOICE.md](docs/VOICE.md).

## Configuration

Your settings live in `~/.claude/monitor/config.json` and the easiest way to change them is through the settings popover in the panel itself. To start fresh, delete `config.json` and run `build.sh` again.

Full config reference: [docs/CONFIGURATION.md](docs/CONFIGURATION.md).

## Reliability and privacy

Agent Monitor keeps session state locally in `~/.claude/monitor/sessions/`.
Session records can contain working directories and prompt previews; permission
records can briefly contain tool names and bounded tool-input details. The
directory is restricted to your account (`0700`) and records use mode `0600`.

Lifecycle updates are merged under per-session cross-process locks and promoted
with atomic writes. If a record is malformed, the app quarantines it as a
hidden `*.corrupt.*` file instead of repeatedly failing to load the panel.
Permission messages use a bounded, versioned, length-prefixed local protocol.
If the app is unavailable or IPC fails, the hook exits cleanly and Claude Code
falls back to its terminal permission dialog.

There is not yet an in-app retention control. Remove old session history by
stopping Agent Monitor and deleting only the files inside
`~/.claude/monitor/sessions/`; they are recreated as new events arrive.

Developer checks:

```bash
swift test
python3 -m unittest discover -s Tests -p 'test_*.py' -v
```

The reliability review, findings, and roadmap live in
[`project/reliability-2026-08/`](project/reliability-2026-08/README.md).

## Troubleshooting

See the full [Troubleshooting Guide](docs/TROUBLESHOOTING.md). The quick fixes:

| Problem | Fix |
|---------|-----|
| Sessions don't appear | Send a prompt in that session to trigger the hook |
| Clicked Allow, nothing happened | Leave the card available for retry; if it persists, gracefully restart with `pkill agent_monitor && ~/.claude/monitor/build.sh` |
| Click doesn't switch tabs | Your terminal may not support click-to-switch (see the compatibility table) |
| No voice | Check `announce.enabled` is on and `volume` > 0 in settings |
| ElevenLabs is silent | Verify your API key and `voice_id` are set — fall back to `say` always works |
| Usage shows "No credentials" | Run `claude login` — or turn usage tracking off in settings |
| Panel disappeared | `pkill agent_monitor && ~/.claude/monitor/build.sh` |

## Uninstall

```bash
pkill agent_monitor
rm -rf ~/.claude/monitor ~/.claude/voice-cache
rm -f ~/.claude/hooks/monitor.sh ~/.claude/hooks/monitor_permission.py ~/.claude/hooks/session_store.py ~/.claude/hooks/session_cleanup.py ~/.claude/hooks/codex_notify.py ~/.claude/hooks/install_codex_notify.py ~/.claude/hooks/voice-cache.sh
```

Then remove the six hook entries (`SessionStart`, `UserPromptSubmit`, `Stop`, `Notification`, `PermissionRequest`, `SessionEnd`) from `~/.claude/settings.json`, and the `notify` line from `~/.codex/config.toml` if you use Codex.

## License

[MIT](LICENSE)

---

<div align="center">
<sub>Built with Claude, naturally.</sub>
</div>
