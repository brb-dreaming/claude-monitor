# P0 Starting Baseline

Captured before P0 implementation on 2026-08-17.

- Git HEAD: `1de7407f35c8d45683275b58964bfe4753c99d1a`.
- Existing modified files: `agent_monitor.swift`, `monitor.sh`,
  `codex_notify.py`, and `install_codex_notify.py`.
- Existing untracked runtime artifact: `codex_notify_chain.json.loop-backup`.
- The reliability-project Markdown files were also untracked.

Pre-P0 SHA-256 values:

```text
72d79c9c19bf0a6130634bfe3959437ffee918e5f902b19c44250f78b69861e9  agent_monitor.swift
180ab7d5ab4f9780905f6d0da0858a8b7da7a2a36fbcbe8d571c499b20f9b7e5  monitor.sh
90d0d9e89c67dbc927645d0ba71446dcf6c5dda8b65bcbbb09244bf7cb0ca2f6  codex_notify.py
3d54703aabb7bf34109515479ba4350ae45dba370b6af847ba4b5f41a4605c90  install_codex_notify.py
b1462cd9f84f11b2c2eb03d80399e7dda786c3d1c0236e70e387db759cc612c0  monitor_permission.py
05f540a05d14aec34355085e2adb9b7045c4ed662e3d8a0919be9b06d  session_cleanup.py
95834a638c825571554b10e8ae89e039fbeb571946db5d6461ff0a3c81fd0ac4  build.sh
```

The original diff was preserved in Git's working tree and P0 changes were
layered on top; none of the pre-existing edits were reverted.
