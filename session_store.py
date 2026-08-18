#!/usr/bin/env python3
"""Transactional cross-process session JSON persistence for Agent Monitor."""

from __future__ import annotations

import argparse
import fcntl
import json
import os
import tempfile
import uuid
from contextlib import contextmanager
from pathlib import Path
from typing import Any, Dict, Iterator


def ensure_private_directory(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    path.chmod(0o700)


@contextmanager
def record_lock(path: Path) -> Iterator[None]:
    ensure_private_directory(path.parent)
    locks = path.parent / ".locks"
    ensure_private_directory(locks)
    lock_path = locks / f"{path.name}.lock"
    descriptor = os.open(lock_path, os.O_CREAT | os.O_RDWR, 0o600)
    os.fchmod(descriptor, 0o600)
    try:
        fcntl.flock(descriptor, fcntl.LOCK_EX)
        yield
    finally:
        fcntl.flock(descriptor, fcntl.LOCK_UN)
        os.close(descriptor)


def _load_unlocked(path: Path) -> Dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError("session record must be a JSON object")
    return value


def _quarantine_unlocked(path: Path) -> None:
    quarantine = path.parent / f".{path.name}.corrupt.{uuid.uuid4()}"
    os.replace(path, quarantine)
    quarantine.chmod(0o600)


def _atomic_write_unlocked(path: Path, value: Dict[str, Any]) -> None:
    ensure_private_directory(path.parent)
    descriptor, temp_name = tempfile.mkstemp(
        prefix=f".{path.name}.", suffix=".tmp", dir=path.parent
    )
    try:
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            json.dump(value, handle, indent=2, sort_keys=True)
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


def apply_event(path: Path, fields: Dict[str, Any], set_prompt: bool) -> Dict[str, Any]:
    with record_lock(path):
        if path.exists():
            try:
                session = _load_unlocked(path)
            except (OSError, ValueError, json.JSONDecodeError):
                _quarantine_unlocked(path)
                session = {}
        else:
            session = {}

        is_new = not session
        if is_new:
            session.update(
                session_id=fields["session_id"],
                project=fields["project"],
                cwd=fields["cwd"],
                terminal=fields["terminal"],
                terminal_session_id=fields["terminal_session_id"],
                started_at=fields["updated_at"],
                last_prompt="",
            )

        session["session_id"] = fields["session_id"]
        session["status"] = fields["status"]
        session["updated_at"] = fields["updated_at"]
        session.setdefault("started_at", fields["updated_at"])
        session.setdefault("project", fields["project"])
        session.setdefault("cwd", fields["cwd"])
        session.setdefault("terminal", "")
        session.setdefault("terminal_session_id", "")
        session.setdefault("last_prompt", "")

        if not session.get("agent"):
            session["agent"] = fields["agent"]
        if fields.get("thread_id") and not session.get("thread_id"):
            session["thread_id"] = fields["thread_id"]
        terminal = fields.get("terminal", "")
        if not session.get("terminal") or (terminal and session.get("terminal") != terminal):
            session["terminal"] = terminal
            session["terminal_session_id"] = fields.get("terminal_session_id", "")
        if set_prompt:
            session["last_prompt"] = fields.get("last_prompt", "")

        _atomic_write_unlocked(path, session)
        return session


def remove_if_done(path: Path, updated_at: str) -> bool:
    with record_lock(path):
        if not path.exists():
            return False
        try:
            session = _load_unlocked(path)
        except (OSError, ValueError, json.JSONDecodeError):
            return False
        if session.get("status") != "done" or session.get("updated_at") != updated_at:
            return False
        path.unlink(missing_ok=True)
        return True


def repair_permissions(sessions_dir: Path) -> None:
    ensure_private_directory(sessions_dir)
    for path in sessions_dir.iterdir():
        if path.is_file() and path.suffix in {".json", ".permission"}:
            path.chmod(0o600)


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    apply_parser = subparsers.add_parser("apply-event")
    apply_parser.add_argument("--file", type=Path, required=True)
    for name in (
        "session-id", "agent", "thread-id", "status", "project", "cwd",
        "terminal", "terminal-session-id", "updated-at", "last-prompt",
    ):
        apply_parser.add_argument(f"--{name}", default="")
    apply_parser.add_argument("--set-prompt", action="store_true")

    remove_parser = subparsers.add_parser("remove-if-done")
    remove_parser.add_argument("--file", type=Path, required=True)
    remove_parser.add_argument("--updated-at", required=True)

    repair_parser = subparsers.add_parser("repair-permissions")
    repair_parser.add_argument("--sessions-dir", type=Path, required=True)
    return parser


def main() -> int:
    args = _parser().parse_args()
    if args.command == "apply-event":
        fields = {
            "session_id": args.session_id,
            "agent": args.agent,
            "thread_id": args.thread_id,
            "status": args.status,
            "project": args.project,
            "cwd": args.cwd,
            "terminal": args.terminal,
            "terminal_session_id": args.terminal_session_id,
            "updated_at": args.updated_at,
            "last_prompt": args.last_prompt,
        }
        apply_event(args.file, fields, args.set_prompt)
    elif args.command == "remove-if-done":
        remove_if_done(args.file, args.updated_at)
    else:
        repair_permissions(args.sessions_dir)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
