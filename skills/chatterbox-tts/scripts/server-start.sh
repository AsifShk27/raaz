#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$script_dir/_env.sh"

if [[ ! -x "$CHATTERBOX_TTS_PYTHON" ]]; then
  echo "Error: Chatterbox runtime python not found: $CHATTERBOX_TTS_PYTHON" >&2
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "Error: curl is required." >&2
  exit 1
fi

if ! [[ "$CHATTERBOX_TTS_STARTUP_TIMEOUT_SECONDS" =~ ^[0-9]+$ ]] || (( CHATTERBOX_TTS_STARTUP_TIMEOUT_SECONDS < 10 )); then
  CHATTERBOX_TTS_STARTUP_TIMEOUT_SECONDS=300
fi

requested_device="${CHATTERBOX_TTS_DEVICE,,}"
if [[ "$requested_device" == "directml" || "$requested_device" == "dml" ]]; then
  echo "[chatterbox-tts] DirectML requested but unstable for Chatterbox in this environment; forcing CPU." >&2
  CHATTERBOX_TTS_DEVICE="cpu"
fi

if [[ -f "$CHATTERBOX_TTS_PID_FILE" ]]; then
  old_pid="$(cat "$CHATTERBOX_TTS_PID_FILE" 2>/dev/null || true)"
  if [[ -n "$old_pid" ]] && kill -0 "$old_pid" 2>/dev/null; then
    if curl -fsS --connect-timeout 2 "$CHATTERBOX_TTS_HEALTH_URL" >/dev/null 2>&1; then
      echo "Chatterbox server already running (PID: $old_pid)."
      exit 0
    fi
  fi
  rm -f "$CHATTERBOX_TTS_PID_FILE"
fi

mkdir -p "$(dirname "$CHATTERBOX_TTS_LOG_FILE")"

nohup "$CHATTERBOX_TTS_PYTHON" "$script_dir/server.py" \
  --host "$CHATTERBOX_TTS_HOST" \
  --port "$CHATTERBOX_TTS_PORT" \
  --device "$CHATTERBOX_TTS_DEVICE" \
  --model "$CHATTERBOX_TTS_MODEL" \
  >>"$CHATTERBOX_TTS_LOG_FILE" 2>&1 &

server_pid=$!
echo "$server_pid" >"$CHATTERBOX_TTS_PID_FILE"

echo "Starting Chatterbox server (PID: $server_pid) on $CHATTERBOX_TTS_HOST:$CHATTERBOX_TTS_PORT ..."

deadline=$((SECONDS + CHATTERBOX_TTS_STARTUP_TIMEOUT_SECONDS))
while (( SECONDS < deadline )); do
  if curl -fsS --connect-timeout 2 "$CHATTERBOX_TTS_HEALTH_URL" >/dev/null 2>&1; then
    echo "Chatterbox server is ready."
    exit 0
  fi
  if ! kill -0 "$server_pid" 2>/dev/null; then
    echo "Chatterbox server exited early. Check $CHATTERBOX_TTS_LOG_FILE" >&2
    rm -f "$CHATTERBOX_TTS_PID_FILE"
    exit 1
  fi
  sleep 1
done

echo "Timed out waiting for Chatterbox server health after ${CHATTERBOX_TTS_STARTUP_TIMEOUT_SECONDS}s." >&2
exit 1
