#!/usr/bin/env python3

import os
import sys
import time
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from session_store import remove_if_done


def main() -> int:
    if len(sys.argv) != 4:
        return 1

    session_file, done_updated_at, permission_file = sys.argv[1:4]
    time.sleep(5)

    if not os.path.exists(session_file):
        return 0

    if remove_if_done(Path(session_file), done_updated_at):
        permission_path = Path(permission_file)
        for path in permission_path.parent.glob(f"{permission_path.stem}*.permission"):
            path.unlink(missing_ok=True)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
