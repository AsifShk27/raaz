#!/usr/bin/env bash
set -euo pipefail

# Prints Piper TTS server status.
# Exits 0 if healthy, 1 otherwise.

script_path="$(readlink -f "${BASH_SOURCE[0]}")"
here="$(cd -- "$(dirname -- "$script_path")" && pwd)"

# shellcheck source=_env.sh
source "$here/_env.sh"

# Check health endpoint
if command -v curl >/dev/null 2>&1; then
  if curl -fsS --max-time 2 "$PIPER_TTS_BASE_URL/health" >/dev/null 2>&1; then
    echo "healthy $PIPER_TTS_BASE_URL"
    exit 0
  fi
fi

# Check if process is running but not healthy yet
if [[ -f "$PIPER_TTS_PID_FILE" ]]; then
  pid="$(cat "$PIPER_TTS_PID_FILE" 2>/dev/null || true)"
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    echo "starting pid=$pid url=$PIPER_TTS_BASE_URL"
    exit 1
  fi
fi

echo "stopped url=$PIPER_TTS_BASE_URL"
exit 1
