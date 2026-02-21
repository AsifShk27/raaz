#!/bin/bash
# VibeVoice TTS Generator
# Generates expressive speech from text using Microsoft's VibeVoice

set -e

# Default configuration
VIBEVOICE_DEVICE="${VIBEVOICE_DEVICE:-cuda}"
VIBEVOICE_MAX_AUDIO_LENGTH="${VIBEVOICE_MAX_AUDIO_LENGTH:-1800}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Generate speech using VibeVoice TTS.

Options:
    --text TEXT          Text to synthesize (required if no --text-file)
    --text-file FILE     File containing text to synthesize
    --output, -o FILE    Output audio file (required)
    --speaker SPEAKER    Speaker preset name (optional)
    --emit-tag           Emit Clawdbot media tag
    --help               Show this help

Environment variables:
    VIBEVOICE_CHECKPOINT    Path to model checkpoint directory (optional)
    VIBEVOICE_DEVICE        Device to use (cuda/cpu)
    VIBEVOICE_MAX_AUDIO_LENGTH  Max audio length in seconds

Example:
    $(basename "$0") --text "Hello world" --output hello.wav
    $(basename "$0") --text-file script.txt --output output.wav --emit-tag
EOF
    exit 1
}

# Parse arguments
OUTPUT=""
TEXT=""
TEXT_FILE=""
SPEAKER=""
EMIT_TAG=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --text)
            TEXT="$2"
            shift 2
            ;;
        --text-file)
            TEXT_FILE="$2"
            shift 2
            ;;
        --output|-o)
            OUTPUT="$2"
            shift 2
            ;;
        --speaker)
            SPEAKER="$2"
            shift 2
            ;;
        --emit-tag)
            EMIT_TAG=true
            shift
            ;;
        --help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Validate inputs
if [[ -z "$TEXT" && -z "$TEXT_FILE" ]]; then
    echo "Error: --text or --text-file is required"
    exit 1
fi

if [[ -z "$OUTPUT" ]]; then
    echo "Error: --output is required"
    exit 1
fi

# Prepare speaker/voice
VOICE="${SPEAKER:-${VIBEVOICE_VOICE:-Samuel}}"

# Build args for voice-note script
ARGS=()
if [[ -n "$TEXT" ]]; then
    ARGS+=(--text "$TEXT")
else
    ARGS+=(--text-file "$TEXT_FILE")
fi
ARGS+=(--out "$OUTPUT" --voice "$VOICE")
if [[ "$EMIT_TAG" == "true" ]]; then
    ARGS+=(--emit-tag)
fi

echo "Generating speech with VibeVoice..."
echo "Device: $VIBEVOICE_DEVICE"
echo "Output: $OUTPUT"

"$SCRIPT_DIR/voice-note-vibevoice.sh" "${ARGS[@]}"
