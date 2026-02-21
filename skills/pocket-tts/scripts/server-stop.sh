#!/usr/bin/env bash
set -euo pipefail

script_path="$(readlink -f "${BASH_SOURCE[0]}")"
here="$(cd -- "$(dirname -- "$script_path")" && pwd)"
# shellcheck source=_env.sh
source "$here/_env.sh"

if [[ ! -f "$POCKET_TTS_PID_FILE" ]]; then
  echo "not running"
  exit 0
fi

pid="$(cat "$POCKET_TTS_PID_FILE" 2>/dev/null || true)"
if [[ -z "$pid" ]]; then
  rm -f "$POCKET_TTS_PID_FILE"
  echo "not running"
  exit 0
fi

if kill -0 "$pid" 2>/dev/null; then
  kill "$pid" 2>/dev/null || true
  # give it a moment
  sleep 2
  if kill -0 "$pid" 2>/dev/null; then
    kill -9 "$pid" 2>/dev/null || true
  fi
fi

rm -f "$POCKET_TTS_PID_FILE"
echo "stopped"
