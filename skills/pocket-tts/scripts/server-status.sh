#!/usr/bin/env bash
set -euo pipefail

# Prints status and exits:
# 0 if healthy, 1 otherwise.

script_path="$(readlink -f "${BASH_SOURCE[0]}")"
here="$(cd -- "$(dirname -- "$script_path")" && pwd)"
# shellcheck source=_env.sh
source "$here/_env.sh"

if command -v curl >/dev/null 2>&1; then
  if curl -fsS --max-time 1 "$POCKET_TTS_BASE_URL/health" >/dev/null 2>&1; then
    echo "healthy $POCKET_TTS_BASE_URL"
    exit 0
  fi
fi

if [[ -f "$POCKET_TTS_PID_FILE" ]]; then
  pid="$(cat "$POCKET_TTS_PID_FILE" 2>/dev/null || true)"
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    echo "running-but-unhealthy pid=$pid url=$POCKET_TTS_BASE_URL"
    exit 1
  fi
fi

echo "stopped url=$POCKET_TTS_BASE_URL"
exit 1
