#!/usr/bin/env bash
set -euo pipefail

# Whisper.cpp Voice Transcription via Warm Server
# Usage: voice-transcribe-warm.sh <audio-file> [--model <model>] [--language <lang>]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
COMMON_DEVICE="$SKILLS_ROOT/_common/device.sh"
if [[ -f "$COMMON_DEVICE" ]]; then
    # shellcheck source=/dev/null
    source "$COMMON_DEVICE"
fi

# Default settings
model="${WHISPER_CPP_MODEL:-large-v3}"
language=""
in=""
WHISPER_CPP_HOST="${WHISPER_CPP_HOST:-127.0.0.1}"
WHISPER_CPP_PORT="${WHISPER_CPP_PORT:-8098}"
device="${WHISPER_CPP_DEVICE:-${OPENCLAW_DEVICE:-}}"
if [[ -z "$device" && "$(type -t openclaw_device_default || true)" == "function" ]]; then
    device="$(openclaw_device_default)"
fi
if [[ "${device,,}" == "auto" && "$(type -t openclaw_device_default || true)" == "function" ]]; then
    device="$(openclaw_device_default)"
fi
[[ -z "$device" ]] && device="auto"

usage() {
    cat <<EOF
Usage: voice-transcribe-warm.sh <audio-file> [options]

Options:
  --model <model>     Model (default: large-v3)
  --language <lang>   Language code
  -h, --help          Show this help

Examples:
  voice-transcribe-warm.sh audio.mp3
  voice-transcribe-warm.sh audio.mp3 --language en
EOF
    exit 2
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --model) model="$2"; shift 2 ;;
        --language) language="$2"; shift 2 ;;
        -h|--help) usage ;;
        -*) echo "Unknown: $1" >&2; usage ;;
        *) [[ -z "$in" ]] && in="$1" || { echo "Multiple: $in and $1" >&2; exit 1; }; shift ;;
    esac
done

# Validate
[[ -z "$in" ]] && { echo "No audio file" >&2; exit 1; }
[[ ! -f "$in" ]] && { echo "Not found: $in" >&2; exit 1; }

# DirectML path: use Python Whisper via voice-to-text-local
if [[ "${device,,}" == "directml" || "${device,,}" == "dml" ]]; then
    vtt="$SKILLS_ROOT/voice-to-text-local/scripts/transcribe.sh"
    if [[ ! -x "$vtt" ]]; then
        echo "Error: Missing voice-to-text-local transcribe script: $vtt" >&2
        exit 1
    fi
    args=("$in" --model "$model" --device directml)
    [[ -n "$language" ]] && args+=(--language "$language")
    "$vtt" "${args[@]}"
    exit $?
fi

# Ensure server is running
"$SCRIPT_DIR/server-control.sh" start >/dev/null 2>&1 || true

# Convert to WAV if needed (server needs WAV)
tmp_wav="/tmp/whisper-warm-$$.wav"
cleanup() { rm -f "$tmp_wav"; }
trap cleanup EXIT

ffmpeg -y -hide_banner -loglevel error -i "$in" -ar 16000 -ac 1 -c:a pcm_s16le "$tmp_wav" 2>/dev/null

if [[ ! -f "$tmp_wav" ]]; then
    echo "Failed to convert audio" >&2
    exit 1
fi

# Send to server via curl
echo "Transcribing via warm server..."

response=$(curl -sS -X POST \
    -F "file=@$tmp_wav" \
    -F "model=$model" \
    ${language:+-F "language=$language"} \
    "$WHISPER_CPP_HOST:$WHISPER_CPP_PORT/transcribe" 2>/dev/null)

if [[ -z "$response" ]]; then
    echo "Empty response from server" >&2
    exit 1
fi

# Output just the text
echo "$response" | jq -r '.text' 2>/dev/null || echo "$response"
