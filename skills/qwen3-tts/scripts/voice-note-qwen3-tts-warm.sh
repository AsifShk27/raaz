#!/bin/bash
#
# Qwen3-TTS Warm Mode Voice Note Generator
# Uses HTTP server for fast synthesis (model pre-loaded)
#
# Usage:
#   voice-note-qwen3-tts-warm.sh --text "Hello" --out /tmp/reply.ogg
#   voice-note-qwen3-tts-warm.sh --text "Hello" --emit-tag
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
SKILLS_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
COMMON_DEVICE="$SKILLS_ROOT/_common/device.sh"
if [[ -f "$COMMON_DEVICE" ]]; then
    # shellcheck source=/dev/null
    source "$COMMON_DEVICE"
fi
SERVER_HOST="${QWEN3_TTS_HOST:-127.0.0.1}"
SERVER_PORT="${QWEN3_TTS_PORT:-8099}"
INSTRUCT="${QWEN3_TTS_INSTRUCT:-Speak with a cheerful American accent in a robotic, futuristic tone.}"
LANGUAGE="${QWEN3_TTS_LANGUAGE:-English}"
DEFAULT_MODEL="Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign"
LOCAL_MODEL_DIR="${QWEN3_TTS_MODEL_DIR:-$HOME/.openclaw/qwen3-tts/models/Qwen3-TTS-12Hz-1.7B-VoiceDesign}"
MODEL="${QWEN3_TTS_MODEL:-}"
if [[ -z "$MODEL" && -n "$LOCAL_MODEL_DIR" ]]; then
    if [[ -f "$LOCAL_MODEL_DIR/config.json" || -f "$LOCAL_MODEL_DIR/model.safetensors" || -f "$LOCAL_MODEL_DIR/pytorch_model.bin" ]]; then
        MODEL="$LOCAL_MODEL_DIR"
    fi
fi
if [[ -z "$MODEL" ]]; then
    MODEL="$DEFAULT_MODEL"
fi
DEVICE="${QWEN3_TTS_DEVICE:-${OPENCLAW_DEVICE:-}}"
if [[ -z "$DEVICE" && "$(type -t openclaw_device_default || true)" == "function" ]]; then
    DEVICE="$(openclaw_device_default)"
fi
if [[ -z "$DEVICE" ]]; then
    DEVICE="auto"
fi
OUTPUT_FILE=""
TEXT=""
EMIT_TAG=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --text)
            TEXT="$2"
            shift 2
            ;;
        --text-file)
            if [[ -f "$2" ]]; then
                TEXT=$(cat "$2")
            else
                echo "Error: Text file not found: $2" >&2
                exit 1
            fi
            shift 2
            ;;
        --out)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --emit-tag)
            EMIT_TAG=true
            shift
            ;;
        --help|-h)
            grep '^#' "$0" | sed 's/^#//' | head -15
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# Validate
[[ -z "$TEXT" ]] && { echo "Error: No text provided" >&2; exit 1; }
[[ "$EMIT_TAG" == "false" && -z "$OUTPUT_FILE" ]] && { echo "Error: No output file" >&2; exit 1; }

# Check if server is running, start if not
if [[ "${DEVICE,,}" == "directml" || "${DEVICE,,}" == "dml" ]]; then
    if ! command -v powershell.exe >/dev/null 2>&1; then
        echo "Error: powershell.exe not found. DirectML path requires Windows PowerShell." >&2
        exit 1
    fi
    PS_STATUS="$(dirname "$0")/server-status.ps1"
    PS_START="$(dirname "$0")/server-start.ps1"
    PS_STOP="$(dirname "$0")/server-stop.ps1"
    BIND_HOST="$SERVER_HOST"
    CALL_HOST="$SERVER_HOST"
    if [[ "$CALL_HOST" == "127.0.0.1" || "$CALL_HOST" == "localhost" ]]; then
        if [[ "$(type -t openclaw_windows_host || true)" == "function" ]]; then
            CALL_HOST="$(openclaw_windows_host)"
            BIND_HOST="0.0.0.0"
        fi
    fi
    PS_STATUS_WIN="$(wslpath -w "$PS_STATUS")"
    PS_START_WIN="$(wslpath -w "$PS_START")"
    PS_STOP_WIN="$(wslpath -w "$PS_STOP")"
    if [[ ! -f "$PS_STATUS" || ! -f "$PS_START" || ! -f "$PS_STOP" ]]; then
        echo "Error: Missing PowerShell server scripts." >&2
        exit 1
    fi
    # Stop WSL warm server to avoid port proxy collisions with Windows DirectML
    if QWEN3_TTS_DEVICE="$DEVICE" "$(dirname "$0")/server-status.sh" | grep -q "Running"; then
        echo "Stopping WSL warm server to free port for Windows DirectML..." >&2
        "$(dirname "$0")/server-stop.sh" >/dev/null 2>&1 || true
        sleep 2
    fi

    HEALTH_URL="http://${CALL_HOST}:${SERVER_PORT}/health"
    HEALTH_OK=false
    if curl -s -m 2 "$HEALTH_URL" | grep -q '"status"'; then
        HEALTH_OK=true
        SERVER_HOST="$CALL_HOST"
    fi

    PS_RUNNING=false
    if powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PS_STATUS_WIN" >/dev/null 2>&1; then
        PS_RUNNING=true
    fi

    if [[ "$PS_RUNNING" == "true" && "$HEALTH_OK" != "true" ]]; then
        echo "Warm server running but not reachable from WSL; restarting..." >&2
        powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PS_STOP_WIN" >/dev/null 2>&1 || true
        PS_RUNNING=false
    fi

    if [[ "$PS_RUNNING" != "true" && "$HEALTH_OK" != "true" ]]; then
        echo "Starting Qwen3-TTS warm server on Windows (DirectML)..."
        MODEL_WIN="$MODEL"
        if [[ -e "$MODEL" ]]; then
            MODEL_WIN="$(wslpath -w "$MODEL")"
        fi
        PS_ARGS=(
            -NoProfile -ExecutionPolicy Bypass -File "$PS_START_WIN"
            -BindHost "$BIND_HOST" -Port "$SERVER_PORT" -Model "$MODEL_WIN" -Device "directml"
        )
        if [[ -n "${OPENCLAW_WIN_PYTHON:-}" ]]; then
            PS_ARGS+=(-PythonPath "${OPENCLAW_WIN_PYTHON}")
        fi
        powershell.exe "${PS_ARGS[@]}"
        if curl -s -m 2 "$HEALTH_URL" | grep -q '"status"'; then
            SERVER_HOST="$CALL_HOST"
            HEALTH_OK=true
        fi
    fi

    if [[ "$HEALTH_OK" != "true" ]]; then
        echo "Error: Windows warm server not reachable from WSL at $HEALTH_URL" >&2
        exit 1
    fi
else
    QWEN3_TTS_DEVICE="$DEVICE" "$(dirname "$0")/server-status.sh" | grep -q "Running" || {
        echo "Starting Qwen3-TTS warm server..."
        QWEN3_TTS_DEVICE="$DEVICE" "$(dirname "$0")/server-start.sh" start
    }
fi

# Set default output
[[ -z "$OUTPUT_FILE" ]] && OUTPUT_FILE="/tmp/qwen3-tts-warm-$(date +%s).ogg"

# Call server API
echo "Generating voice note via warm server..." >&2

payload=$(
  TEXT="$TEXT" INSTRUCT="$INSTRUCT" LANGUAGE="$LANGUAGE" \
  python3 - <<'PY'
import json
import os
payload = {
    "text": os.environ.get("TEXT", ""),
    "instruct": os.environ.get("INSTRUCT", ""),
    "language": os.environ.get("LANGUAGE", "English"),
    "speed": 1.0
}
print(json.dumps(payload))
PY
)

if [[ "${DEVICE,,}" == "directml" || "${DEVICE,,}" == "dml" ]]; then
    SERVER_HOST="$CALL_HOST"
fi

RESPONSE=$(curl -s -X POST "http://${SERVER_HOST}:${SERVER_PORT}/tts" \
    -H "Content-Type: application/json" \
    -d "$payload")

# Parse response
AUDIO_HEX=$(echo "$RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('audio', ''))" 2>/dev/null)

if [[ -z "$AUDIO_HEX" ]]; then
    echo "Error: Failed to generate audio" >&2
    echo "Response: $RESPONSE" >&2
    exit 1
fi

# Decode and save
echo "$AUDIO_HEX" | xxd -r -p > "$OUTPUT_FILE"

if [[ -f "$OUTPUT_FILE" ]]; then
    echo "✅ Voice note: $OUTPUT_FILE" >&2
    
    if [[ "$EMIT_TAG" == "true" ]]; then
        echo "[[audio_as_voice]]"
        echo "MEDIA:$OUTPUT_FILE"
    fi
else
    echo "❌ Failed to save audio" >&2
    exit 1
fi
