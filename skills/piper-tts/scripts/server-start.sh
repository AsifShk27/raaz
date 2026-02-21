#!/usr/bin/env bash
set -euo pipefail

# Starts Piper TTS server in background if not healthy.
# Waits until /health responds or times out.

script_path="$(readlink -f "${BASH_SOURCE[0]}")"
here="$(cd -- "$(dirname -- "$script_path")" && pwd)"

# shellcheck source=_env.sh
source "$here/_env.sh"

wait_seconds="${PIPER_TTS_START_TIMEOUT_SECONDS:-60}"

# Check if already healthy (skip model check if server is running)
if command -v curl >/dev/null 2>&1; then
  if curl -fsS --max-time 2 "$PIPER_TTS_BASE_URL/health" >/dev/null 2>&1; then
    exit 0
  fi
fi

# Need to start server - check if model is configured
if [[ -z "$PIPER_VOICE_MODEL" ]]; then
  echo "PIPER_VOICE_MODEL not set. Cannot start server." >&2
  exit 1
fi

if [[ ! -f "$PIPER_VOICE_MODEL" ]]; then
  echo "Model file not found: $PIPER_VOICE_MODEL" >&2
  exit 1
fi

# If pid exists but process dead, remove it
if [[ -f "$PIPER_TTS_PID_FILE" ]]; then
  old_pid="$(cat "$PIPER_TTS_PID_FILE" 2>/dev/null || true)"
  if [[ -n "$old_pid" ]] && ! kill -0 "$old_pid" 2>/dev/null; then
    rm -f "$PIPER_TTS_PID_FILE"
  fi
fi

# If pid exists and running, just wait for health
if [[ -f "$PIPER_TTS_PID_FILE" ]]; then
  pid="$(cat "$PIPER_TTS_PID_FILE" 2>/dev/null || true)"
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    : # Process running, wait for health below
  else
    rm -f "$PIPER_TTS_PID_FILE"
  fi
fi

# Start server if no pid file
if [[ ! -f "$PIPER_TTS_PID_FILE" ]]; then
  # Build server args (use PIPER_TTS_PYTHON for deps)
  server_args=(
    "$PIPER_TTS_PYTHON" "$here/piper_server.py"
    --host "$PIPER_TTS_HOST"
    --port "$PIPER_TTS_PORT"
    --model "$PIPER_VOICE_MODEL"
    --piper-bin "$PIPER_BIN"
    --length-scale "$PIPER_LENGTH_SCALE"
    --noise-scale "$PIPER_NOISE_SCALE"
    --noise-w "$PIPER_NOISE_W"
  )

  if [[ -n "$PIPER_VOICE_CONFIG" ]]; then
    server_args+=(--config "$PIPER_VOICE_CONFIG")
  fi

  if [[ -n "$PIPER_SPEAKER" ]]; then
    server_args+=(--speaker "$PIPER_SPEAKER")
  fi

  echo "Starting Piper TTS server..." >&2
  echo "Model: $PIPER_VOICE_MODEL" >&2
  echo "URL: $PIPER_TTS_BASE_URL" >&2

  # Launch in background
  nohup "${server_args[@]}" >>"$PIPER_TTS_LOG_FILE" 2>&1 &
  echo $! >"$PIPER_TTS_PID_FILE"

  echo "Server PID: $(cat "$PIPER_TTS_PID_FILE")" >&2
fi

# Wait for health
echo "Waiting for server to become healthy (timeout: ${wait_seconds}s)..." >&2
start_ts="$(date +%s)"
while true; do
  if command -v curl >/dev/null 2>&1; then
    if curl -fsS --max-time 2 "$PIPER_TTS_BASE_URL/health" >/dev/null 2>&1; then
      echo "Server is healthy!" >&2
      exit 0
    fi
  fi

  # Check if process died
  if [[ -f "$PIPER_TTS_PID_FILE" ]]; then
    pid="$(cat "$PIPER_TTS_PID_FILE" 2>/dev/null || true)"
    if [[ -n "$pid" ]] && ! kill -0 "$pid" 2>/dev/null; then
      echo "Server process died. Check log: $PIPER_TTS_LOG_FILE" >&2
      rm -f "$PIPER_TTS_PID_FILE"
      exit 1
    fi
  fi

  now="$(date +%s)"
  if (( now - start_ts >= wait_seconds )); then
    echo "Server did not become healthy within ${wait_seconds}s." >&2
    echo "Log: $PIPER_TTS_LOG_FILE" >&2
    exit 1
  fi
  sleep 1
done
