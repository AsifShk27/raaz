#!/usr/bin/env bash
set -euo pipefail

# Whisper.cpp Server - Warm mode for Clawdbot voice transcription
# Keeps model loaded in memory for fast repeated transcriptions

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Config
WHISPER_CPP_VENV="${WHISPER_CPP_VENV:-/home/shkas/pocket-tts/venv}"
WHISPER_CPP_HOST="${WHISPER_CPP_HOST:-127.0.0.1}"
WHISPER_CPP_PORT="${WHISPER_CPP_PORT:-8098}"
WHISPER_CPP_MODEL="${WHISPER_CPP_MODEL:-large-v3}"
WHISPER_CPP_STATE_DIR="${WHISPER_CPP_STATE_DIR:-$HOME/.openclaw/whisper-cpp}"
WHISPER_CPP_PID_FILE="$WHISPER_CPP_STATE_DIR/server.pid"
WHISPER_CPP_LOG_FILE="$WHISPER_CPP_STATE_DIR/server.log"

mkdir -p "$WHISPER_CPP_STATE_DIR"

# Find whisper-cli
WHISPER_CLI=""
if command -v whisper-cli >/dev/null 2>&1; then
    WHISPER_CLI="whisper-cli"
elif [[ -x "/home/linuxbrew/.linuxbrew/bin/whisper-cli" ]]; then
    WHISPER_CLI="/home/linuxbrew/.linuxbrew/bin/whisper-cli"
else
    echo "Error: whisper-cli not found" >&2
    exit 1
fi

# Model file
model_file="$HOME/.cache/whisper/ggml-${WHISPER_CPP_MODEL}.bin"
[[ ! -f "$model_file" ]] && { echo "Model not found: $model_file" >&2; exit 1; }

# Status check
status() {
    if command -v curl >/dev/null 2>&1; then
        if curl -fsS --max-time 1 "$WHISPER_CPP_HOST:$WHISPER_CPP_PORT/health" >/dev/null 2>&1; then
            echo "healthy $WHISPER_CPP_HOST:$WHISPER_CPP_PORT"
            exit 0
        fi
    fi
    if [[ -f "$WHISPER_CPP_PID_FILE" ]]; then
        pid="$(cat "$WHISPER_CPP_PID_FILE" 2>/dev/null || true)"
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            echo "running-but-unhealthy pid=$pid url=$WHISPER_CPP_HOST:$WHISPER_CPP_PORT"
            exit 1
        fi
    fi
    echo "stopped url=$WHISPER_CPP_HOST:$WHISPER_CPP_PORT"
    exit 1
}

# Start server
start_server() {
    if [[ -f "$WHISPER_CPP_PID_FILE" ]]; then
        pid="$(cat "$WHISPER_CPP_PID_FILE" 2>/dev/null || true)"
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            echo "Already running (pid=$pid)"
            return 0
        fi
        rm -f "$WHISPER_CPP_PID_FILE"
    fi

    echo "Starting whisper.cpp server..."
    echo "Model: $WHISPER_CPP_MODEL"
    echo "URL: $WHISPER_CPP_HOST:$WHISPER_CPP_PORT"

    # Check if whisper.cpp has server mode
    "$WHISPER_CLI" --help 2>&1 | grep -q "server"
    has_server=$?

    if [[ $has_server -eq 0 ]]; then
        # whisper.cpp has built-in server mode
        nohup "$WHISPER_CLI" \
            -m "$model_file" \
            --port "$WHISPER_CPP_PORT" \
            --host "$WHISPER_CPP_HOST" \
            -t 4 \
            >>"$WHISPER_CPP_LOG_FILE" 2>&1 &
        echo $! > "$WHISPER_CPP_PID_FILE"
    else
        # No server mode, use simple approach - keep warm by running in background
        # This will process one request and stay ready
        echo "whisper.cpp doesn't have persistent server mode"
        echo "Creating simple warm-keepalive approach..."
    fi

    # Wait for health
    start_ts=$(date +%s)
    while true; do
        if command -v curl >/dev/null 2>&1; then
            if curl -fsS --max-time 1 "$WHISPER_CPP_HOST:$WHISPER_CPP_PORT/health" >/dev/null 2>&1; then
                echo "Server healthy!"
                return 0
            fi
        fi
        sleep 1
        if (( $(date +%s) - start_ts >= 60 )); then
            echo "Timeout waiting for server"
            return 1
        fi
    done
}

# Stop server
stop_server() {
    if [[ ! -f "$WHISPER_CPP_PID_FILE" ]]; then
        echo "Not running"
        return 0
    fi
    pid="$(cat "$WHISPER_CPP_PID_FILE" 2>/dev/null || true)"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true
        sleep 2
        kill -9 "$pid" 2>/dev/null || true
    fi
    rm -f "$WHISPER_CPP_PID_FILE"
    echo "Stopped"
}

# Main
case "${1:-status}" in
    status) status ;;
    start) start_server ;;
    stop) stop_server ;;
    *)
        echo "Usage: $0 {status|start|stop}"
        exit 1
        ;;
esac
