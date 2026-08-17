#!/usr/bin/env python3

import ast
import json
import re
import shutil
import tempfile
from pathlib import Path
from typing import List, Optional, Tuple, Union


HOME = Path.home()
CONFIG_PATH = HOME / ".codex" / "config.toml"
BACKUP_PATH = HOME / ".codex" / "config.toml.agent-monitor.bak"
LEGACY_BACKUP_PATH = HOME / ".codex" / "config.toml.claude-monitor.bak"
CHAIN_PATH = HOME / ".claude" / "monitor" / "codex_notify_chain.json"
HOOK_NOTIFY = ["python3", str(HOME / ".claude" / "hooks" / "codex_notify.py")]
Command = Union[List[str], str]
NOTIFY_PATTERN = re.compile(r"^\s*notify\s*=")


def read_text(path: Path) -> str:
    try:
        return path.read_text()
    except FileNotFoundError:
        return ""


def atomic_write_text(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", dir=path.parent, delete=False) as handle:
        handle.write(content)
        temp_path = Path(handle.name)
    temp_path.replace(path)


def strip_inline_comment(line: str) -> str:
    result = []
    in_single = False
    in_double = False
    escaped = False

    for ch in line:
        if in_double:
            result.append(ch)
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == "\"":
                in_double = False
            continue

        if in_single:
            result.append(ch)
            if ch == "'":
                in_single = False
            continue

        if ch == "#":
            break
        if ch == "\"":
            in_double = True
        elif ch == "'":
            in_single = True
        result.append(ch)

    return "".join(result)


def bracket_delta(text: str) -> int:
    cleaned = strip_inline_comment(text)
    in_single = False
    in_double = False
    escaped = False
    delta = 0

    for ch in cleaned:
        if in_double:
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == "\"":
                in_double = False
            continue

        if in_single:
            if ch == "'":
                in_single = False
            continue

        if ch == "\"":
            in_double = True
        elif ch == "'":
            in_single = True
        elif ch == "[":
            delta += 1
        elif ch == "]":
            delta -= 1

    return delta


def extract_notify_assignment(text: str) -> Tuple[Optional[int], Optional[int], Optional[str]]:
    if not text.strip():
        return None, None, None

    lines = text.splitlines(keepends=True)
    start = None
    end = None
    bracket_depth = 0

    for index, line in enumerate(lines):
        stripped = line.lstrip()
        if start is None:
            if not stripped or stripped.startswith("#"):
                continue
            if stripped.startswith("["):
                break
            if NOTIFY_PATTERN.match(line):
                start = index
                _, rhs = line.split("=", 1)
                bracket_depth = bracket_delta(rhs)
                if bracket_depth <= 0:
                    end = index + 1
                    break
        else:
            bracket_depth += bracket_delta(line)
            if bracket_depth <= 0:
                end = index + 1
                break

    if start is None:
        return None, None, None
    if end is None:
        end = len(lines)

    first_line = lines[start]
    _, rhs = first_line.split("=", 1)
    raw_value = rhs + "".join(lines[start + 1 : end])
    return start, end, raw_value


def parse_notify_value(raw_value: str) -> Optional[Command]:
    cleaned_lines = []
    for line in raw_value.splitlines():
        stripped = strip_inline_comment(line).strip()
        if stripped:
            cleaned_lines.append(stripped)

    cleaned = "\n".join(cleaned_lines).strip()
    if not cleaned:
        return None

    try:
        parsed = ast.literal_eval(cleaned)
    except (SyntaxError, ValueError):
        return None

    if isinstance(parsed, str):
        return parsed
    if isinstance(parsed, list) and all(isinstance(part, str) for part in parsed):
        return parsed
    return None


def parse_notify(path: Path) -> Tuple[bool, Optional[Command]]:
    text = read_text(path)
    _, _, raw_value = extract_notify_assignment(text)
    if raw_value is None:
        return False, None
    return True, parse_notify_value(raw_value)


def load_chain_config() -> Optional[Command]:
    try:
        data = json.loads(CHAIN_PATH.read_text())
    except (OSError, json.JSONDecodeError):
        return None

    command = data.get("command")
    if isinstance(command, str) and command.strip():
        return command
    if isinstance(command, list) and all(isinstance(part, str) for part in command):
        return command
    return None


def write_chain_config(command: Optional[Command]) -> None:
    payload = {"command": command}
    atomic_write_text(CHAIN_PATH, json.dumps(payload, indent=2, sort_keys=True) + "\n")


def is_self_command(command: Optional[Command]) -> bool:
    if command is None:
        return False

    self_path = str(HOME / ".claude" / "hooks" / "codex_notify.py")
    if isinstance(command, list):
        # A command can embed us inside one of its own arguments rather than
        # naming us as a whole part — Codex's computer-use client registers as
        # `... turn-ended --previous-notify '["python3","<self>"]'`, JSON-escaped
        # slashes and all. Preserving that as the "previous" notifier is what
        # builds a notify loop, so match on a de-escaped substring too.
        return any(
            Path(part).expanduser() == Path(self_path)
            or self_path in part.replace("\\/", "/")
            for part in command
        )
    return self_path in command.replace("\\/", "/")


def replace_top_level_notify(text: str, notify_line: str) -> str:
    if not text.strip():
        return notify_line + "\n"

    lines = text.splitlines(keepends=True)
    start, end, _ = extract_notify_assignment(text)

    if start is not None and end is not None:
        lines[start:end] = [notify_line + "\n"]
        return "".join(lines)

    insert_at = None
    for index, line in enumerate(lines):
        stripped = line.lstrip()
        if stripped.startswith("["):
            insert_at = index
            break

    if insert_at is None:
        if lines and not lines[-1].endswith("\n"):
            lines[-1] += "\n"
        lines.append(notify_line + "\n")
        return "".join(lines)

    prefix = lines[:insert_at]
    if prefix and prefix[-1].strip():
        prefix.append("\n")
    prefix.append(notify_line + "\n")
    return "".join(prefix + lines[insert_at:])


def main() -> int:
    CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)

    original = read_text(CONFIG_PATH)
    notify_exists, existing_notify = parse_notify(CONFIG_PATH)
    if notify_exists and existing_notify is None:
        print(f"Could not safely parse existing notify setting in {CONFIG_PATH}; leaving file unchanged.")
        return 1

    existing_chain = load_chain_config()
    if is_self_command(existing_notify):
        if not CHAIN_PATH.exists():
            write_chain_config(existing_chain)
        print(f"Codex notify already configured in {CONFIG_PATH}")
        return 0

    preserved_command = existing_notify if existing_notify is not None else None
    if existing_chain is not None and preserved_command is None and is_self_command(existing_chain):
        preserved_command = None

    if original and not BACKUP_PATH.exists() and not LEGACY_BACKUP_PATH.exists():
        shutil.copy2(CONFIG_PATH, BACKUP_PATH)

    write_chain_config(preserved_command)

    notify_line = f"notify = {json.dumps(HOOK_NOTIFY)}"
    updated = replace_top_level_notify(original, notify_line)
    atomic_write_text(CONFIG_PATH, updated)
    print(f"Configured Codex notify in {CONFIG_PATH}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
