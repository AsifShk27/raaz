#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STOP_PS="$SCRIPT_DIR/stop-server.ps1"

if [[ ! -f "$STOP_PS" ]]; then
  echo "[embeddings-directml] stop script missing: $STOP_PS" >&2
  exit 1
fi

if ! command -v powershell.exe >/dev/null 2>&1; then
  echo "[embeddings-directml] powershell.exe not found; cannot stop Windows embeddings server." >&2
  exit 1
fi

STOP_PS_WIN="$(wslpath -w "$STOP_PS")"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$STOP_PS_WIN"
