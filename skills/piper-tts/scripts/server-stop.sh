#!/usr/bin/env bash
set -euo pipefail

# Stops Piper TTS server if running.

script_path="$(readlink -f "${BASH_SOURCE[0]}")"
here="$(cd -- "$(dirname -- "$script_path")" && pwd)"

# shellcheck source=_env.sh
source "$here/_env.sh"

if [[ ! -f "$PIPER_TTS_PID_FILE" ]]; then
  echo "No PID file found. Server not running." >&2
  exit 0
fi

pid="$(cat "$PIPER_TTS_PID_FILE" 2>/dev/null || true)"

if [[ -z "$pid" ]]; then
  rm -f "$PIPER_TTS_PID_FILE"
  echo "Empty PID file. Cleaned up." >&2
  exit 0
fi

if ! kill -0 "$pid" 2>/dev/null; then
  rm -f "$PIPER_TTS_PID_FILE"
  echo "Process $pid not running. Cleaned up PID file." >&2
  exit 0
fi

echo "Stopping Piper TTS server (PID: $pid)..." >&2

# Try graceful termination first
kill "$pid" 2>/dev/null || true
sleep 1

# Force kill if still running
if kill -0 "$pid" 2>/dev/null; then
  echo "Process still running, sending SIGKILL..." >&2
  kill -9 "$pid" 2>/dev/null || true
  sleep 0.5
fi

rm -f "$PIPER_TTS_PID_FILE"
echo "Server stopped." >&2
