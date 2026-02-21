#!/usr/bin/env bash
set -euo pipefail

# Starts Pocket TTS server in background if not healthy.
# Waits until /health responds or times out.

script_path="$(readlink -f "${BASH_SOURCE[0]}")"
here="$(cd -- "$(dirname -- "$script_path")" && pwd)"
# shellcheck source=_env.sh
source "$here/_env.sh"

wait_seconds="${POCKET_TTS_START_TIMEOUT_SECONDS:-180}"

# Already healthy?
if command -v curl >/dev/null 2>&1; then
  if curl -fsS --max-time 1 "$POCKET_TTS_BASE_URL/health" >/dev/null 2>&1; then
    exit 0
  fi
fi

# If pid exists but dead, remove it
if [[ -f "$POCKET_TTS_PID_FILE" ]]; then
  old_pid="$(cat "$POCKET_TTS_PID_FILE" 2>/dev/null || true)"
  if [[ -n "$old_pid" ]] && ! kill -0 "$old_pid" 2>/dev/null; then
    rm -f "$POCKET_TTS_PID_FILE"
  fi
fi

# If pid exists and running, just wait for health
if [[ -f "$POCKET_TTS_PID_FILE" ]]; then
  pid="$(cat "$POCKET_TTS_PID_FILE" 2>/dev/null || true)"
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    :
  else
    rm -f "$POCKET_TTS_PID_FILE"
  fi
fi

# Start server
if [[ ! -f "$POCKET_TTS_PID_FILE" ]]; then
  if [[ ! -d "$POCKET_TTS_VENV" ]]; then
    echo "Pocket TTS venv not found: $POCKET_TTS_VENV" >&2
    exit 1
  fi

  # shellcheck disable=SC1090
  source "$POCKET_TTS_VENV/bin/activate"

  # Launch in background, keep logs.
  # Important: bind to 127.0.0.1 only.
  nohup pocket-tts serve \
    --host "$POCKET_TTS_HOST" \
    --port "$POCKET_TTS_PORT" \
    --voice "$POCKET_TTS_DEFAULT_VOICE" \
    --device "$POCKET_TTS_DEVICE" \
    >>"$POCKET_TTS_LOG_FILE" 2>&1 &

  echo $! >"$POCKET_TTS_PID_FILE"
fi

# Wait for health
start_ts="$(date +%s)"
while true; do
  if command -v curl >/dev/null 2>&1; then
    if curl -fsS --max-time 1 "$POCKET_TTS_BASE_URL/health" >/dev/null 2>&1; then
      exit 0
    fi
  fi
  now="$(date +%s)"
  if (( now - start_ts >= wait_seconds )); then
    echo "Pocket TTS server did not become healthy within ${wait_seconds}s." >&2
    echo "Log: $POCKET_TTS_LOG_FILE" >&2
    exit 1
  fi
  sleep 1
done
