#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$script_dir/_env.sh"

if [[ ! -f "$CHATTERBOX_TTS_PID_FILE" ]]; then
  echo "Chatterbox server not running (no pidfile)."
  exit 0
fi

pid="$(cat "$CHATTERBOX_TTS_PID_FILE" 2>/dev/null || true)"
rm -f "$CHATTERBOX_TTS_PID_FILE"

if [[ -z "$pid" ]]; then
  echo "Chatterbox pidfile was empty."
  exit 0
fi

if kill -0 "$pid" 2>/dev/null; then
  kill "$pid" 2>/dev/null || true
  for _ in {1..20}; do
    if ! kill -0 "$pid" 2>/dev/null; then
      echo "Chatterbox server stopped."
      exit 0
    fi
    sleep 0.2
  done
  kill -9 "$pid" 2>/dev/null || true
fi

echo "Chatterbox server stopped."
