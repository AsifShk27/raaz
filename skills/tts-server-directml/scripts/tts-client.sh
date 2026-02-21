#!/bin/bash
#
# TTS Client - Calls Windows TTS server from WSL2
#
# Usage:
#   tts-client.sh --text "Hello" --out /tmp/speech.ogg
#   tts-client.sh --text-file /tmp/text.txt --out /tmp/speech.ogg --model kokoro
#

set -e

# Load shared helpers
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
COMMON_DEVICE="$SKILLS_ROOT/_common/device.sh"
if [[ -f "$COMMON_DEVICE" ]]; then
    # shellcheck source=/dev/null
    source "$COMMON_DEVICE"
fi

# Defaults
SERVER_HOST="${TTS_SERVER_HOST:-localhost}"
SERVER_PORT="${TTS_SERVER_PORT:-8099}"
MODEL="${TTS_MODEL:-piper}"
VOICE=""
FORMAT="ogg"
INSTRUCT=""
LANGUAGE=""
OUTPUT_FILE=""
TEXT=""
EMIT_TAG=false
FAST=false

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
        --model)
            MODEL="$2"
            shift 2
            ;;
        --voice)
            VOICE="$2"
            shift 2
            ;;
        --instruct)
            INSTRUCT="$2"
            shift 2
            ;;
        --language)
            LANGUAGE="$2"
            shift 2
            ;;
        --format)
            FORMAT="$2"
            shift 2
            ;;
        --emit-tag)
            EMIT_TAG=true
            shift
            ;;
        --fast)
            FAST=true
            shift
            ;;
        --server)
            SERVER_HOST="$2"
            shift 2
            ;;
        --port)
            SERVER_PORT="$2"
            shift 2
            ;;
        --help|-h)
            echo "TTS Client - Calls Windows TTS server"
            echo ""
            echo "Usage:"
            echo "  $0 --text \"Hello\" --out /tmp/speech.ogg"
            echo "  $0 --text-file input.txt --out output.ogg --model kokoro"
            echo ""
            echo "Options:"
            echo "  --text        Text to synthesize"
            echo "  --text-file   Read text from file"
            echo "  --out         Output audio file path"
            echo "  --model       TTS model: piper, kokoro, edge, qwen3 (default: piper)"
            echo "  --voice       Voice ID (model-specific)"
            echo "  --instruct    Qwen3 instruction prompt"
            echo "  --language    Language hint (e.g., English, en)"
            echo "  --format      Output format: ogg, wav, mp3 (default: ogg)"
            echo "  --emit-tag    Print MEDIA tag for Clawdbot"
            echo "  --fast        Enable Qwen3 fast mode for this request"
            echo "  --server      Server host (default: localhost)"
            echo "  --port        Server port (default: 8099)"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# WSL -> Windows host fix
if [[ -z "${TTS_SERVER_HOST:-}" ]]; then
    if [[ "$SERVER_HOST" == "localhost" || "$SERVER_HOST" == "127.0.0.1" ]]; then
        if [[ "$(type -t openclaw_windows_host || true)" == "function" ]]; then
            SERVER_HOST="$(openclaw_windows_host)"
        fi
    fi
fi

# Validate
if [[ -z "$TEXT" ]]; then
    echo "Error: No text provided. Use --text or --text-file" >&2
    exit 1
fi

if [[ -z "$OUTPUT_FILE" && "$EMIT_TAG" == "false" ]]; then
    echo "Error: No output file specified. Use --out" >&2
    exit 1
fi

# Default output file
if [[ -z "$OUTPUT_FILE" ]]; then
    OUTPUT_FILE="/tmp/tts-$(date +%s).${FORMAT}"
fi

# Build JSON payload
JSON_PAYLOAD=$(cat <<EOF
{
    "text": $(echo "$TEXT" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'),
    "model": "$MODEL",
    "format": "$FORMAT"
EOF
)

# Add voice if specified
if [[ -n "$VOICE" ]]; then
    JSON_PAYLOAD="${JSON_PAYLOAD}, \"voice\": \"$VOICE\""
fi
if [[ "$FAST" == "true" ]]; then
    JSON_PAYLOAD="${JSON_PAYLOAD}, \"fast\": true"
fi

# Add Qwen3-specific fields if provided
if [[ -n "$INSTRUCT" ]]; then
    JSON_PAYLOAD="${JSON_PAYLOAD}, \"instruct\": $(echo "$INSTRUCT" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')"
fi
if [[ -n "$LANGUAGE" ]]; then
    JSON_PAYLOAD="${JSON_PAYLOAD}, \"language\": \"$LANGUAGE\""
fi

JSON_PAYLOAD="${JSON_PAYLOAD}}"

# Check server health first
if ! curl -s --connect-timeout 2 "http://${SERVER_HOST}:${SERVER_PORT}/health" > /dev/null 2>&1; then
    echo "Error: TTS server not reachable at http://${SERVER_HOST}:${SERVER_PORT}" >&2
    echo "Start the server on Windows: python scripts/server.py" >&2
    exit 1
fi

# Call TTS API
HTTP_CODE=$(curl -s -w "%{http_code}" \
    -X POST "http://${SERVER_HOST}:${SERVER_PORT}/tts" \
    -H "Content-Type: application/json" \
    -d "$JSON_PAYLOAD" \
    --output "$OUTPUT_FILE")

if [[ "$HTTP_CODE" != "200" ]]; then
    echo "Error: TTS request failed with HTTP $HTTP_CODE" >&2
    if [[ -f "$OUTPUT_FILE" ]]; then
        cat "$OUTPUT_FILE" >&2
        rm -f "$OUTPUT_FILE"
    fi
    exit 1
fi

# Verify output
if [[ -f "$OUTPUT_FILE" && -s "$OUTPUT_FILE" ]]; then
    echo "Generated: $OUTPUT_FILE" >&2

    if [[ "$EMIT_TAG" == "true" ]]; then
        echo "[[audio_as_voice]]"
        echo "MEDIA:$OUTPUT_FILE"
    fi
else
    echo "Error: Output file empty or not created" >&2
    exit 1
fi
