#!/bin/bash
# VibeVoice Multi-Speaker Conversation Generator
# Generates podcast-style conversations with multiple speakers

set -e

VIBEVOICE_CHECKPOINT="${VIBEVOICE_CHECKPOINT:-}"
VIBEVOICE_DEVICE="${VIBEVOICE_DEVICE:-cuda}"
VIBEVOICE_SERVER_URL="${VIBEVOICE_SERVER_URL:-http://127.0.0.1:7860}"
VIBEVOICE_SPEAKER_A="${VIBEVOICE_SPEAKER_A:-Carter}"
VIBEVOICE_SPEAKER_B="${VIBEVOICE_SPEAKER_B:-Grace}"
VIBEVOICE_SPEAKER_C="${VIBEVOICE_SPEAKER_C:-Frank}"
VIBEVOICE_SPEAKER_D="${VIBEVOICE_SPEAKER_D:-Emma}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    cat << EOF2
Usage: $(basename "$0") [OPTIONS]

Generate multi-speaker conversation using VibeVoice.

Options:
    --script FILE       Script file with speaker labels (required)
    --output, -o FILE   Output audio file (required)
    --emit-tag          Emit Clawdbot media tag
    --help              Show this help

Script format:
    [SPEAKER_A] Hello, welcome to the show!
    [SPEAKER_B] Thanks for having me!
    [SPEAKER_A] Today we're discussing...

Speaker labels: SPEAKER_A, SPEAKER_B, SPEAKER_C, SPEAKER_D (up to 4)

Environment variables:
    VIBEVOICE_CHECKPOINT    Path to model checkpoint directory
    VIBEVOICE_DEVICE        Device to use (cuda/cpu)
    VIBEVOICE_SERVER_URL    Warm server URL (optional)
    VIBEVOICE_SPEAKER_A     Voice preset for SPEAKER_A (default: Carter)
    VIBEVOICE_SPEAKER_B     Voice preset for SPEAKER_B (default: Grace)
    VIBEVOICE_SPEAKER_C     Voice preset for SPEAKER_C (default: Frank)
    VIBEVOICE_SPEAKER_D     Voice preset for SPEAKER_D (default: Emma)

Example:
    $(basename "$0") --script conversation.txt --output podcast.wav
EOF2
    exit 1
}

# Parse arguments
OUTPUT=""
SCRIPT=""
EMIT_TAG=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --script)
            SCRIPT="$2"
            shift 2
            ;;
        --output|-o)
            OUTPUT="$2"
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
if [[ -z "$SCRIPT" ]]; then
    echo "Error: --script is required"
    exit 1
fi

if [[ ! -f "$SCRIPT" ]]; then
    echo "Error: Script file not found: $SCRIPT"
    exit 1
fi

if [[ -z "$OUTPUT" ]]; then
    echo "Error: --output is required"
    exit 1
fi

echo "Generating multi-speaker conversation..."
echo "Script: $SCRIPT"
echo "Output: $OUTPUT"

# Map speaker labels to voice presets
resolve_voice() {
    case "$1" in
        SPEAKER_A) echo "$VIBEVOICE_SPEAKER_A" ;;
        SPEAKER_B) echo "$VIBEVOICE_SPEAKER_B" ;;
        SPEAKER_C) echo "$VIBEVOICE_SPEAKER_C" ;;
        SPEAKER_D) echo "$VIBEVOICE_SPEAKER_D" ;;
        *) echo "$VIBEVOICE_SPEAKER_A" ;;
    esac
}

SEGMENTS_FILE=$(mktemp)
python - "$SCRIPT" << 'PYTHON_EOF' > "$SEGMENTS_FILE"
import sys
import re

pattern = re.compile(r'^\s*\[(SPEAKER_[A-D])\]\s*(.+)$')
with open(sys.argv[1], "r", encoding="utf-8") as f:
    for line in f:
        match = pattern.match(line.strip())
        if not match:
            continue
        speaker, text = match.group(1), match.group(2).strip()
        if text:
            print(f"{speaker}\t{text}")
PYTHON_EOF

TEMP_DIR=$(mktemp -d)
CONCAT_LIST="$TEMP_DIR/concat.txt"
COMBINED_WAV="$TEMP_DIR/combined.wav"
trap 'rm -rf "$TEMP_DIR" "$SEGMENTS_FILE"' EXIT

SERVER_READY=false
if command -v jq >/dev/null 2>&1; then
    if curl -s --connect-timeout 2 "$VIBEVOICE_SERVER_URL/health" >/dev/null 2>&1; then
        SERVER_READY=true
    fi
fi

if [[ "$SERVER_READY" == "true" ]]; then
    echo "Using warm server at $VIBEVOICE_SERVER_URL"
else
    echo "Warm server not available; using local inference"
fi

SEG_INDEX=0
while IFS=$'\t' read -r speaker text; do
    [[ -z "$text" ]] && continue
    voice="$(resolve_voice "$speaker")"
    segment_out="$TEMP_DIR/segment_${SEG_INDEX}.wav"
    echo "Generating $speaker ($voice): ${text:0:60}..."
    if [[ "$SERVER_READY" == "true" ]]; then
        "$SCRIPT_DIR/voice-note-client.sh" --text "$text" --out "$segment_out" --voice "$voice"
    else
        "$SCRIPT_DIR/voice-note-vibevoice.sh" --text "$text" --out "$segment_out" --voice "$voice"
    fi
    echo "file '$segment_out'" >> "$CONCAT_LIST"
    SEG_INDEX=$((SEG_INDEX + 1))
done < "$SEGMENTS_FILE"

if [[ $SEG_INDEX -eq 0 ]]; then
    echo "Error: No valid speaker lines found in script" >&2
    exit 1
fi

ffmpeg -y -f concat -safe 0 -i "$CONCAT_LIST" -c copy "$COMBINED_WAV" 2>/dev/null

OUTPUT_EXT="${OUTPUT##*.}"
if [[ "$OUTPUT_EXT" == "ogg" ]]; then
    ffmpeg -y -i "$COMBINED_WAV" -c:a libopus -b:a 32k -ar 48000 -ac 1 -application voip "$OUTPUT" 2>/dev/null
elif [[ "$OUTPUT_EXT" == "mp3" ]]; then
    ffmpeg -y -i "$COMBINED_WAV" -c:a libmp3lame -b:a 64k "$OUTPUT" 2>/dev/null
else
    cp "$COMBINED_WAV" "$OUTPUT"
fi

# Emit Clawdbot tag if requested
if [[ "$EMIT_TAG" == "true" ]]; then
    echo ""
    echo "MEDIA:$OUTPUT"
fi

echo "Done!"
