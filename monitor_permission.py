#!/usr/bin/env python3
"""Claude PermissionRequest bridge for Agent Monitor's framed Unix socket."""

from __future__ import annotations

import json
import os
import re
import socket
import struct
import sys
import tempfile
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict

TIMEOUT_SECONDS = 300
MAX_FRAME_BYTES = 1_048_576
SESSION_ID_RE = re.compile(r"^[A-Za-z0-9_-]{1,128}$")
REQUEST_ID_RE = re.compile(r"^[A-Za-z0-9_-]{1,128}$")


def monitor_dir() -> Path:
    return Path(
        os.environ.get("AGENT_MONITOR_DIR")
        or os.environ.get("CLAUDE_MONITOR_DIR")
        or Path.home() / ".claude" / "monitor"
    )


def recv_exact(sock: socket.socket, count: int) -> bytes:
    chunks = bytearray()
    while len(chunks) < count:
        chunk = sock.recv(count - len(chunks))
        if not chunk:
            raise EOFError("socket closed mid-frame")
        chunks.extend(chunk)
    return bytes(chunks)


def send_frame(sock: socket.socket, payload: bytes) -> None:
    if len(payload) > MAX_FRAME_BYTES:
        raise ValueError("permission frame is too large")
    sock.sendall(struct.pack("!I", len(payload)) + payload)


def recv_frame(sock: socket.socket) -> bytes:
    (length,) = struct.unpack("!I", recv_exact(sock, 4))
    if length > MAX_FRAME_BYTES:
        raise ValueError("permission response frame is too large")
    return recv_exact(sock, length)


def atomic_write_json(path: Path, value: Dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    path.parent.chmod(0o700)
    descriptor, temp_name = tempfile.mkstemp(
        prefix=f".{path.name}.", suffix=".tmp", dir=path.parent
    )
    try:
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            json.dump(value, handle, sort_keys=True)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temp_name, path)
        path.chmod(0o600)
    except BaseException:
        try:
            os.close(descriptor)
        except OSError:
            pass
        try:
            os.unlink(temp_name)
        except FileNotFoundError:
            pass
        raise


def cleanup(path: Path) -> None:
    path.unlink(missing_ok=True)


def load_input(raw: str) -> Dict[str, Any] | None:
    try:
        value = json.loads(raw)
    except (json.JSONDecodeError, TypeError):
        return None
    return value if isinstance(value, dict) else None


def main() -> int:
    input_data = load_input(sys.stdin.read())
    if input_data is None:
        return 0

    session_id = str(input_data.get("session_id") or "")
    if not SESSION_ID_RE.fullmatch(session_id):
        return 0

    candidate_request_id = str(input_data.get("tool_use_id") or "")
    request_id = (
        candidate_request_id
        if REQUEST_ID_RE.fullmatch(candidate_request_id)
        else uuid.uuid4().hex
    )
    tool_name = str(input_data.get("tool_name") or "")
    tool_input = input_data.get("tool_input")
    if not isinstance(tool_input, dict):
        tool_input = {}

    if tool_name == "Bash":
        display = str(tool_input.get("command") or "")[:300]
    elif tool_name in ("Edit", "Write", "Read"):
        display = str(tool_input.get("file_path") or "")[:300]
    else:
        display = json.dumps(tool_input, ensure_ascii=False)[:300]

    tool_input_json = json.dumps(tool_input, ensure_ascii=False)[:65_536]
    sessions_dir = monitor_dir() / "sessions"
    permission_file = sessions_dir / f"{session_id}.{request_id}.permission"
    permission = {
        "request_id": request_id,
        "session_id": session_id,
        "tool_name": tool_name,
        "display": display,
        "tool_input": tool_input_json,
        "timestamp": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
    }
    try:
        atomic_write_json(permission_file, permission)
    except OSError:
        return 0

    request = {
        "type": "permission_request",
        "protocol_version": 1,
        "request_id": request_id,
        "session_id": session_id,
        "timeout_seconds": TIMEOUT_SECONDS,
    }
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(TIMEOUT_SECONDS)
    try:
        sock.connect(str(monitor_dir() / "monitor.sock"))
        send_frame(sock, json.dumps(request).encode("utf-8"))
        response_data = recv_frame(sock)
        response = json.loads(response_data.decode("utf-8"))
        if not isinstance(response, dict):
            return 0
    except (OSError, EOFError, ValueError, json.JSONDecodeError, UnicodeDecodeError):
        return 0
    finally:
        sock.close()
        cleanup(permission_file)

    decision = response.get("decision")
    if decision == "allow":
        print(json.dumps({
            "hookSpecificOutput": {
                "hookEventName": "PermissionRequest",
                "decision": {"behavior": "allow"},
            }
        }))
    elif decision == "deny":
        print(json.dumps({
            "hookSpecificOutput": {
                "hookEventName": "PermissionRequest",
                "decision": {
                    "behavior": "deny",
                    "message": "Denied from Agent Monitor",
                },
            }
        }))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
