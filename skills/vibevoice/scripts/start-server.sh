#!/bin/bash
# Start VibeVoice warm server in background
# Run this once, then use voice-note-client.sh for fast TTS

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON="${VIBEVOICE_PYTHON:-/usr/bin/python3.12}"
PORT="${VIBEVOICE_SERVER_PORT:-7860}"
LOG_FILE="/tmp/vibevoice-server.log"
PID_FILE="/tmp/vibevoice-server.pid"

# Prefer CPU on WSL for reliability unless explicitly forced.
IS_WSL=false
if [[ -n "${WSL_DISTRO_NAME:-}" ]]; then
    IS_WSL=true
elif [[ -r /proc/version ]] && grep -qi microsoft /proc/version; then
    IS_WSL=true
fi
if [[ "$IS_WSL" == "true" ]]; then
    device_lower="${VIBEVOICE_DEVICE:-}"
    device_lower="${device_lower,,}"
    if [[ "$device_lower" == "directml" || "$device_lower" == "dml" ]]; then
        if [[ -z "${VIBEVOICE_FORCE_DIRECTML:-}" ]]; then
            echo "WSL detected; forcing VIBEVOICE_DEVICE=cpu for reliability. Set VIBEVOICE_FORCE_DIRECTML=1 to override."
            export VIBEVOICE_DEVICE="cpu"
        fi
    fi
fi

case "${1:-start}" in
    start)
        # Check if already running
        if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
            echo "VibeVoice server already running (PID: $(cat "$PID_FILE"))"
            exit 0
        fi
        
        echo "Starting VibeVoice server on port $PORT..."
        echo "Log file: $LOG_FILE"
        
        # Start server in background
        nohup $PYTHON "$SCRIPT_DIR/vibevoice-server.py" --port "$PORT" > "$LOG_FILE" 2>&1 &
        PID=$!
        echo "$PID" > "$PID_FILE"
        
        echo "Server starting (PID: $(cat "$PID_FILE"))"
        echo "Waiting for model to load (this takes ~60 seconds on first run)..."
        
        # Wait for server to be ready
        for i in {1..120}; do
            if ! kill -0 "$PID" 2>/dev/null; then
                echo "Error: Server process exited early. Check $LOG_FILE"
                rm -f "$PID_FILE"
                exit 1
            fi
            if curl -s --connect-timeout 1 "http://127.0.0.1:$PORT/health" > /dev/null 2>&1; then
                echo "VibeVoice server is ready!"
                exit 0
            fi
            sleep 1
            # Show progress
            if (( i % 10 == 0 )); then
                echo "  Still loading... ($i seconds)"
            fi
        done
        
        echo "Error: Server failed to start. Check $LOG_FILE"
        exit 1
        ;;
    
    stop)
        if [[ -f "$PID_FILE" ]]; then
            PID=$(cat "$PID_FILE")
            if kill -0 "$PID" 2>/dev/null; then
                echo "Stopping VibeVoice server (PID: $PID)..."
                kill "$PID"
                rm -f "$PID_FILE"
                echo "Stopped"
            else
                echo "Server not running"
                rm -f "$PID_FILE"
            fi
        else
            echo "No PID file found"
        fi
        ;;
    
    status)
        if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
            echo "VibeVoice server running (PID: $(cat "$PID_FILE"))"
            curl -s "http://127.0.0.1:$PORT/health" | jq .
        else
            echo "VibeVoice server not running"
        fi
        ;;
    
    logs)
        tail -f "$LOG_FILE"
        ;;
    
    restart)
        $0 stop
        sleep 2
        $0 start
        ;;
    
    *)
        echo "Usage: $(basename "$0") {start|stop|status|logs|restart}"
        exit 1
        ;;
esac
