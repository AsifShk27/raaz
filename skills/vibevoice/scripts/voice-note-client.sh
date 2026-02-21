#!/bin/bash
# VibeVoice TTS Client - Connects to warm server
# Drop-in replacement for piper-tts voice-note script

set -e

VIBEVOICE_SERVER_URL="${VIBEVOICE_SERVER_URL:-http://127.0.0.1:7860}"
VIBEVOICE_VOICE="${VIBEVOICE_VOICE:-Carter}"
VIBEVOICE_MAX_CHARS="${VIBEVOICE_MAX_CHARS:-6000}"

usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Generate voice note using VibeVoice TTS server.

Options:
    --text TEXT          Text to synthesize (required if no --text-file)
    --text-file FILE     File containing text to synthesize
    --out, -o FILE       Output audio file (required)
    --voice NAME         Voice preset name (default: Carter)
    --emit-tag           Emit Clawdbot media tag
    --help               Show this help

Environment variables:
    VIBEVOICE_SERVER_URL    Server URL (default: http://127.0.0.1:7860)
    VIBEVOICE_VOICE         Default voice preset
    VIBEVOICE_MAX_CHARS     Max characters (default: 6000)

Example:
    $(basename "$0") --text "Hello world" --out output.ogg
    $(basename "$0") --text-file reply.txt --out reply.ogg --voice Emma --emit-tag
EOF
    exit 1
}

# Parse arguments
OUTPUT=""
TEXT=""
TEXT_FILE=""
VOICE="$VIBEVOICE_VOICE"
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
        --out|-o)
            OUTPUT="$2"
            shift 2
            ;;
        --voice)
            VOICE="$2"
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
            echo "Unknown option: $1" >&2
            usage
            ;;
    esac
done

# Validate inputs
if [[ -z "$TEXT" && -z "$TEXT_FILE" ]]; then
    echo "Error: --text or --text-file is required" >&2
    exit 1
fi

if [[ -z "$OUTPUT" ]]; then
    echo "Error: --out is required" >&2
    exit 1
fi

# Get text content
if [[ -n "$TEXT_FILE" && -f "$TEXT_FILE" ]]; then
    TEXT=$(cat "$TEXT_FILE")
fi

# Truncate if too long
if [[ ${#TEXT} -gt $VIBEVOICE_MAX_CHARS ]]; then
    echo "Warning: Text truncated to $VIBEVOICE_MAX_CHARS chars" >&2
    TEXT="${TEXT:0:$VIBEVOICE_MAX_CHARS}"
fi

# Skip if text is empty
if [[ -z "$TEXT" || "$TEXT" =~ ^[[:space:]]*$ ]]; then
    echo "Warning: Empty text, skipping generation" >&2
    exit 0
fi

# Check if server is running
if ! curl -s --connect-timeout 2 "$VIBEVOICE_SERVER_URL/health" > /dev/null 2>&1; then
    echo "Error: VibeVoice server not running at $VIBEVOICE_SERVER_URL" >&2
    echo "Start it with: /home/shkas/projects/raaz/skills/vibevoice/scripts/start-server.sh" >&2
    exit 1
fi

# Determine output format
OUTPUT_EXT="${OUTPUT##*.}"
TEMP_WAV=$(mktemp --suffix=.wav)

echo "Generating speech via VibeVoice server..." >&2
echo "  Voice: $VOICE" >&2
echo "  Text length: ${#TEXT} chars" >&2

# Call server
HTTP_CODE=$(curl -s -w "%{http_code}" -o "$TEMP_WAV" \
    -X POST "$VIBEVOICE_SERVER_URL/tts" \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg text "$TEXT" --arg voice "$VOICE" '{text: $text, voice: $voice}')")

if [[ "$HTTP_CODE" != "200" ]]; then
    echo "Error: Server returned HTTP $HTTP_CODE" >&2
    cat "$TEMP_WAV" >&2
    rm -f "$TEMP_WAV"
    exit 1
fi

# Convert to output format
if [[ "$OUTPUT_EXT" == "ogg" ]]; then
    ffmpeg -y -i "$TEMP_WAV" -c:a libopus -b:a 32k -ar 48000 -ac 1 -application voip "$OUTPUT" 2>/dev/null
elif [[ "$OUTPUT_EXT" == "mp3" ]]; then
    ffmpeg -y -i "$TEMP_WAV" -c:a libmp3lame -b:a 64k "$OUTPUT" 2>/dev/null
else
    cp "$TEMP_WAV" "$OUTPUT"
fi

rm -f "$TEMP_WAV"

echo "Generated: $OUTPUT" >&2

# Emit Clawdbot tag if requested
if [[ "$EMIT_TAG" == "true" ]]; then
    echo ""
    echo "[[audio_as_voice]]"
    echo "MEDIA:$OUTPUT"
fi
