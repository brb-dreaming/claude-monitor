from __future__ import annotations

import json
import os
import socket
import subprocess
import sys
import tempfile
import threading
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

import monitor_permission
import session_store


class SessionStoreTests(unittest.TestCase):
    def test_concurrent_hook_events_do_not_corrupt_session(self) -> None:
        home = Path(tempfile.mkdtemp())
        monitor = home / ".claude" / "monitor"
        environment = os.environ.copy()
        environment.update(HOME=str(home), AGENT_MONITOR_DIR=str(monitor))
        base = {"session_id": "race-test", "cwd": "/tmp/project"}

        start = subprocess.run(
            ["bash", str(ROOT / "monitor.sh"), "SessionStart"],
            input=json.dumps(base), text=True, env=environment,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )
        self.assertEqual(start.returncode, 0, start.stderr)

        def invoke(index: int) -> subprocess.CompletedProcess[str]:
            event = ("UserPromptSubmit", "Notification", "Stop")[index % 3]
            payload = dict(base)
            if event == "UserPromptSubmit":
                payload["prompt"] = f"prompt-{index}"
            return subprocess.run(
                ["bash", str(ROOT / "monitor.sh"), event],
                input=json.dumps(payload), text=True, env=environment,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            )

        with ThreadPoolExecutor(max_workers=20) as pool:
            results = list(pool.map(invoke, range(60)))

        self.assertEqual([r.returncode for r in results], [0] * 60)
        session_file = monitor / "sessions" / "race-test.json"
        session = json.loads(session_file.read_text())
        self.assertEqual(session["session_id"], "race-test")
        self.assertIn(session["status"], {"working", "attention", "done"})
        self.assertEqual(session_file.stat().st_mode & 0o777, 0o600)
        self.assertEqual(session_file.parent.stat().st_mode & 0o777, 0o700)
        self.assertEqual(list(session_file.parent.glob("*.tmp")), [])

    def test_corrupt_record_is_quarantined(self) -> None:
        root = Path(tempfile.mkdtemp())
        path = root / "sessions" / "s.json"
        path.parent.mkdir()
        path.write_text("{broken")
        fields = dict(
            session_id="s", agent="claude", thread_id="", status="working",
            project="p", cwd="/tmp/p", terminal="", terminal_session_id="",
            updated_at="now", last_prompt="prompt",
        )
        session_store.apply_event(path, fields, True)
        self.assertEqual(json.loads(path.read_text())["status"], "working")
        self.assertTrue(any(".corrupt." in p.name for p in path.parent.iterdir()))


class PermissionHookTests(unittest.TestCase):
    def test_malformed_input_fails_open_without_traceback(self) -> None:
        for raw in ("", "{", "[]", '"string"'):
            result = subprocess.run(
                [sys.executable, str(ROOT / "monitor_permission.py")],
                input=raw, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            )
            self.assertEqual(result.returncode, 0)
            self.assertEqual(result.stderr, "")

    def test_framed_permission_round_trip_and_private_file(self) -> None:
        root = Path(tempfile.mkdtemp())
        socket_path = root / "monitor.sock"
        server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        server.bind(str(socket_path))
        server.listen(1)
        observed: dict[str, object] = {}

        def serve() -> None:
            connection, _ = server.accept()
            with connection:
                observed.update(json.loads(monitor_permission.recv_frame(connection)))
                payload = json.dumps({"decision": "allow"}).encode()
                framed = len(payload).to_bytes(4, "big") + payload
                for byte in framed:
                    connection.sendall(bytes([byte]))

        thread = threading.Thread(target=serve)
        thread.start()
        event = {
            "session_id": "session-1",
            "tool_use_id": "toolu_123",
            "tool_name": "Bash",
            "tool_input": {"command": "echo hello"},
        }
        environment = os.environ.copy()
        environment["AGENT_MONITOR_DIR"] = str(root)
        result = subprocess.run(
            [sys.executable, str(ROOT / "monitor_permission.py")],
            input=json.dumps(event), text=True, env=environment,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )
        thread.join(timeout=5)
        server.close()

        self.assertEqual(result.returncode, 0, result.stderr)
        output = json.loads(result.stdout)
        self.assertEqual(
            output["hookSpecificOutput"]["decision"]["behavior"], "allow"
        )
        self.assertEqual(observed["protocol_version"], 1)
        self.assertEqual(observed["request_id"], "toolu_123")
        self.assertEqual(observed["timeout_seconds"], 300)
        self.assertEqual(list((root / "sessions").glob("*.permission")), [])
        self.assertEqual((root / "sessions").stat().st_mode & 0o777, 0o700)


if __name__ == "__main__":
    unittest.main()
