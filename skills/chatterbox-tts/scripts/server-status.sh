#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$script_dir/_env.sh"

if [[ -f "$CHATTERBOX_TTS_PID_FILE" ]]; then
  pid="$(cat "$CHATTERBOX_TTS_PID_FILE" 2>/dev/null || true)"
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    echo "Chatterbox server running (PID: $pid)"
    curl -fsS --connect-timeout 2 "$CHATTERBOX_TTS_HEALTH_URL" || true
    exit 0
  fi
fi

echo "Chatterbox server not running"
exit 1
