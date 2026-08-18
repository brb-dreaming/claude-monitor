#!/usr/bin/env python3

import json
import os
import shlex
import subprocess
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Union


def utc_now() -> str:
    from datetime import datetime, timezone

    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def truncate(text: str, limit: int = 200) -> str:
    return text[:limit]


def load_event(raw: str) -> Optional[Dict[str, Any]]:
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError:
        return None
    if not isinstance(payload, dict):
        return None
    return payload


def load_json(path: Path) -> Dict[str, Any]:
    try:
        data = json.loads(path.read_text())
        if isinstance(data, dict):
            return data
    except (OSError, json.JSONDecodeError):
        pass
    return {}


def hook_script_path() -> Path:
    return Path.home() / ".claude" / "hooks" / "codex_notify.py"


def is_self_command(command: Union[List[str], str]) -> bool:
    self_path = str(hook_script_path())
    if isinstance(command, list):
        # Whole-part equality is not enough. A chained notifier can carry us
        # inside one of its own arguments — Codex's computer-use client is
        # registered as `SkyComputerUseClient turn-ended --previous-notify
        # '["python3","~/.claude/hooks/codex_notify.py"]'`, where the reference
        # back to this script is a JSON blob, not a bare path. Matching only
        # exact parts misses it, we call the client, the client calls us, and a
        # single turn-complete event ping-pongs forever.
        # The reference is also JSON-escaped ("\/Users\/bp\/..."), so compare
        # against a de-escaped copy of each argument rather than the raw text.
        return any(
            Path(part).expanduser() == Path(self_path)
            or self_path in part.replace("\\/", "/")
            for part in command
        )
    return self_path in command.replace("\\/", "/")


def load_chain_command() -> Optional[Union[List[str], str]]:
    chain_path = Path.home() / ".claude" / "monitor" / "codex_notify_chain.json"
    try:
        data = json.loads(chain_path.read_text())
    except (OSError, json.JSONDecodeError):
        return None

    command = data.get("command")
    if isinstance(command, list) and all(isinstance(part, str) for part in command):
        if is_self_command(command):
            return None
        return command
    if isinstance(command, str) and command.strip():
        if is_self_command(command):
            return None
        return command
    return None


def run_chained_notifier(raw_event: str) -> None:
    command = load_chain_command()
    if not command:
        return

    try:
        if isinstance(command, list):
            subprocess.run(command + [raw_event], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
        else:
            subprocess.run(
                ["/bin/sh", "-c", f"{command} {shlex.quote(raw_event)}"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
            )
    except Exception:
        pass


def choose_session_id(sessions_dir: Path, session_id: str, cwd: str, thread_id: str) -> Optional[str]:
    if session_id:
        return session_id

    cwd_matches: List[str] = []
    for path in sessions_dir.glob("*.json"):
        session = load_json(path)
        if session.get("agent") != "codex":
            continue
        if thread_id and session.get("thread_id") == thread_id:
            return str(session.get("session_id") or "").strip() or None
        if cwd and session.get("cwd") == cwd:
            cwd_matches.append(str(session.get("session_id") or "").strip())

    if thread_id:
        safe_thread = "".join(ch for ch in thread_id if ch.isalnum() or ch in "-_")
        if safe_thread:
            return f"codex-{safe_thread}"

    matches = [match for match in cwd_matches if match]
    if len(matches) == 1:
        return matches[0]
    return None


def main() -> int:
    if len(sys.argv) < 2:
        return 0

    raw_event = sys.argv[1]
    event = load_event(raw_event)
    if not event or event.get("type") != "agent-turn-complete":
        return 0

    monitor_dir = Path(
        os.environ.get("AGENT_MONITOR_DIR")
        or os.environ.get("CLAUDE_MONITOR_DIR")
        or str(Path.home() / ".claude" / "monitor")
    )
    sessions_dir = monitor_dir / "sessions"
    thread_id = str(event.get("thread-id") or "").strip()
    cwd = str(
        event.get("cwd")
        or os.environ.get("AGENT_MONITOR_CWD")
        or os.environ.get("CLAUDE_MONITOR_CWD", "")
    ).strip()
    input_messages = event.get("input-messages")
    prompt = ""
    if isinstance(input_messages, list) and input_messages:
        prompt = truncate(str(input_messages[0]).strip())
    session_id = choose_session_id(
        sessions_dir=sessions_dir,
        session_id=str(
            os.environ.get("AGENT_MONITOR_SESSION_ID")
            or os.environ.get("CLAUDE_MONITOR_SESSION_ID", "")
        ).strip(),
        cwd=cwd,
        thread_id=thread_id,
    )
    if not session_id:
        return 0

    session_file = sessions_dir / f"{session_id}.json"
    should_autoclean = not session_file.exists() and session_id.startswith("codex-")
    monitor_hook = Path.home() / ".claude" / "hooks" / "monitor.sh"
    if monitor_hook.exists():
        payload = json.dumps({"session_id": session_id, "cwd": cwd, "prompt": prompt})
        env = dict(os.environ)
        env["AGENT_MONITOR_AGENT"] = "codex"
        if thread_id:
            env["AGENT_MONITOR_THREAD_ID"] = thread_id
        if should_autoclean:
            env["AGENT_MONITOR_AUTOCLEAN_DONE"] = "1"
        subprocess.run(
            [str(monitor_hook), "Stop"],
            input=payload,
            text=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            env=env,
            check=False,
        )

    run_chained_notifier(raw_event)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
