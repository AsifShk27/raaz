---
name: codexbar-usage
description: Capture CodexBar usage snapshots (web/cli) and write a JSON file for Collab routing decisions.
metadata: {"openclaw":{"emoji":"📈","requires":{"bins":["codexbar","powershell.exe"]}}}
---

# CodexBar Usage Snapshot

Capture CodexBar usage as JSON and write it to a shared location so Collab can route
requests based on usage limits.

## Files

- WSL/Linux script: `scripts/codexbar-usage-snapshot.sh`
- Windows script: `scripts/codexbar-usage-snapshot.ps1`

## WSL / Linux usage (recommended for Collab)

```bash
COLLAB_USAGE_SOURCE=cli \
COLLAB_USAGE_PATH="$AGENT_COLLAB_ROOT/usage/codexbar-usage.json" \
./scripts/codexbar-usage-snapshot.sh
```

## Windows usage (optional for web source)

Run from Windows PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "\\wsl$\Ubuntu\home\shkas\projects\raaz\skills\codexbar-usage\scripts\codexbar-usage-snapshot.ps1" -Source web
```

If web source is unsupported, the script falls back to `cli`.

## Environment variables

- `COLLAB_USAGE_SOURCE` — `web` or `cli` (default: `cli`)
- `COLLAB_USAGE_PROVIDER` — provider (default: `codex`)
- `COLLAB_USAGE_PATH` — output JSON path (default uses `$AGENT_COLLAB_ROOT/usage/codexbar-usage.json`)
