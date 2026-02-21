#!/usr/bin/env bash
set -euo pipefail

# Whisper.cpp Transcription Script for Clawdbot
# Usage: transcribe.sh <audio-file> [--model <model>] [--language <lang>]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
COMMON_DEVICE="$SKILLS_ROOT/_common/device.sh"
if [[ -f "$COMMON_DEVICE" ]]; then
    # shellcheck source=/dev/null
    source "$COMMON_DEVICE"
fi

# Default settings
model="${WHISPER_CPP_MODEL:-base}"
language=""
in=""
threads="${WHISPER_CPP_THREADS:-4}"
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
Usage: transcribe.sh <audio-file> [options]

Options:
  --model <model>     Model (tiny, base, small, medium, large-v3)
                      Default: base
  --language <lang>   Language code (e.g., en, hi, ta, ml)
                      Default: auto-detect
  --threads <n>       CPU threads (default: 4)
  -h, --help          Show this help

Examples:
  transcribe.sh audio.mp3
  transcribe.sh audio.mp3 --model small --language en
EOF
    exit 2
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --model) model="$2"; shift 2 ;;
        --language) language="$2"; shift 2 ;;
        --threads) threads="$2"; shift 2 ;;
        -h|--help) usage ;;
        -*)
            echo "Unknown option: $1" >&2
            usage
            ;;
        *)
            [[ -z "$in" ]] && in="$1" || { echo "Multiple files: $in and $1" >&2; exit 1; }
            shift
            ;;
    esac
done

# Validate input
[[ -z "$in" ]] && { echo "No audio file" >&2; exit 1; }
[[ ! -f "$in" ]] && { echo "File not found: $in" >&2; exit 1; }

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

# Find whisper-cli binary (Homebrew installs as whisper-cli)
WHISPER_CPP_BIN=""
if command -v whisper-cli >/dev/null 2>&1; then
    WHISPER_CPP_BIN="whisper-cli"
elif [[ -x "/home/linuxbrew/.linuxbrew/bin/whisper-cli" ]]; then
    WHISPER_CPP_BIN="/home/linuxbrew/.linuxbrew/bin/whisper-cli"
else
    echo "Error: whisper-cli not found" >&2
    echo "Install with: brew install whisper-cpp" >&2
    exit 1
fi

# Model file path
model_file="$HOME/.cache/whisper/ggml-${model}.bin"
[[ ! -f "$model_file" ]] && { echo "Model not found: $model_file" >&2; exit 1; }

# Convert audio to WAV if needed (whisper.cpp needs WAV)
tmp_wav="/tmp/whisper-temp-$$.wav"
cleanup() { rm -f "$tmp_wav"; }
trap cleanup EXIT

# Convert to WAV (whisper.cpp requires WAV input)
ffmpeg -y -hide_banner -loglevel error -i "$in" -ar 16000 -ac 1 -c:a pcm_s16le "$tmp_wav" 2>/dev/null

if [[ ! -f "$tmp_wav" ]]; then
    echo "Error: Failed to convert audio to WAV" >&2
    exit 1
fi

# Build command
cmd=(
    "$WHISPER_CPP_BIN"
    -m "$model_file"
    -f "$tmp_wav"
    -t "$threads"
)

# Add language if specified
[[ -n "$language" ]] && cmd+=(-l "$language")

# Run and output transcribed text
# whisper.cpp outputs progress to stderr, transcript to stdout
transcript=$("${cmd[@]}" 2>/dev/null)
echo "$transcript"
