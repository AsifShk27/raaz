#!/bin/bash
# VibeVoice TTS for Clawdbot voice replies
# Drop-in replacement for piper-tts voice-note script

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
COMMON_DEVICE="$SKILLS_ROOT/_common/device.sh"
if [[ -f "$COMMON_DEVICE" ]]; then
    # shellcheck source=/dev/null
    source "$COMMON_DEVICE"
fi
VIBEVOICE_ROOT="/home/shkas/projects/raaz/VibeVoice"
VIBEVOICE_CHECKPOINT="${VIBEVOICE_CHECKPOINT:-/home/shkas/projects/raaz/VibeVoice/checkpoints/VibeVoice-Realtime-0.5B}"
VIBEVOICE_DEVICE="${VIBEVOICE_DEVICE:-${OPENCLAW_DEVICE:-}}"
if [[ -z "$VIBEVOICE_DEVICE" && "$(type -t openclaw_device_default || true)" == "function" ]]; then
    VIBEVOICE_DEVICE="$(openclaw_device_default)"
fi
if [[ "${VIBEVOICE_DEVICE,,}" == "auto" && "$(type -t openclaw_device_default || true)" == "function" ]]; then
    VIBEVOICE_DEVICE="$(openclaw_device_default)"
fi
[[ -z "$VIBEVOICE_DEVICE" ]] && VIBEVOICE_DEVICE="cpu"

# Prefer CPU on WSL for reliability unless explicitly forced.
IS_WSL=false
if [[ -n "${WSL_DISTRO_NAME:-}" ]]; then
    IS_WSL=true
elif [[ -r /proc/version ]] && grep -qi microsoft /proc/version; then
    IS_WSL=true
fi
if [[ "$IS_WSL" == "true" ]]; then
    device_lower="${VIBEVOICE_DEVICE,,}"
    if [[ "$device_lower" == "directml" || "$device_lower" == "dml" ]]; then
        if [[ -z "${VIBEVOICE_FORCE_DIRECTML:-}" ]]; then
            echo "Note: WSL detected; forcing CPU for reliability. Set VIBEVOICE_FORCE_DIRECTML=1 to override." >&2
            VIBEVOICE_DEVICE="cpu"
        fi
    fi
fi
VIBEVOICE_VOICE="${VIBEVOICE_VOICE:-Samuel}"
VIBEVOICE_CFG_SCALE="${VIBEVOICE_CFG_SCALE:-1.5}"
VIBEVOICE_MAX_CHARS="${VIBEVOICE_MAX_CHARS:-6000}"
PYTHON="${VIBEVOICE_PYTHON:-/usr/bin/python3.12}"

usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Generate voice note using VibeVoice TTS.

Options:
    --text TEXT          Text to synthesize (required if no --text-file)
    --text-file FILE     File containing text to synthesize
    --out, -o FILE       Output audio file (required)
    --voice NAME         Voice preset name (default: Samuel)
    --emit-tag           Emit Clawdbot media tag
    --help               Show this help

Environment variables:
    VIBEVOICE_CHECKPOINT    Path to model checkpoint
    VIBEVOICE_DEVICE        Device: cuda, mps, directml, cpu (default: auto)
    VIBEVOICE_VOICE         Default voice preset
    VIBEVOICE_CFG_SCALE     CFG scale (default: 1.5)
    VIBEVOICE_MAX_CHARS     Max characters (default: 6000)
    VIBEVOICE_PYTHON        Python interpreter (default: /usr/bin/python3.12)
    OPENCLAW_DEVICE         Global device hint (auto/directml/cuda/cpu)
    OPENCLAW_WIN_PYTHON      Windows Python for DirectML (e.g. C:\\Python312\\python.exe)

Available voices:
    English: Carter, Davis, Mike, Frank, Emma, Grace, Samuel (Indian)
    Other: de-Spk0, fr-Spk0, it-Spk0, jp-Spk0, kr-Spk0, zh-Spk0, etc.

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

# Create temp file for text
TEMP_TXT=$(mktemp --suffix=.txt)
echo "$TEXT" > "$TEMP_TXT"

# DirectML path (Windows)
if [[ "${VIBEVOICE_DEVICE,,}" == "directml" || "${VIBEVOICE_DEVICE,,}" == "dml" ]]; then
    if ! command -v powershell.exe >/dev/null 2>&1; then
        echo "Error: powershell.exe not found. DirectML path requires Windows PowerShell." >&2
        rm -f "$TEMP_TXT"
        exit 1
    fi
    PS_SCRIPT="${SCRIPT_DIR}/voice-note-vibevoice-directml.ps1"
    if [[ ! -f "$PS_SCRIPT" ]]; then
        echo "Error: Missing PowerShell script: $PS_SCRIPT" >&2
        rm -f "$TEMP_TXT"
        exit 1
    fi
    PS_SCRIPT_WIN="$(wslpath -w "$PS_SCRIPT")"

    PS_ARGS=(
        -NoProfile -ExecutionPolicy Bypass -File "$PS_SCRIPT_WIN"
        -TextFile "$(wslpath -w "$TEMP_TXT")"
        -Out "$(wslpath -w "$OUTPUT")"
        -Voice "$VOICE"
        -Checkpoint "$(wslpath -w "$VIBEVOICE_CHECKPOINT")"
        -RepoRoot "$(wslpath -w "$VIBEVOICE_ROOT")"
        -CfgScale "$VIBEVOICE_CFG_SCALE"
        -MaxChars "$VIBEVOICE_MAX_CHARS"
    )
    if [[ -n "${OPENCLAW_WIN_PYTHON:-}" ]]; then
        PS_ARGS+=(-PythonPath "${OPENCLAW_WIN_PYTHON}")
    fi
    set +e
    powershell.exe "${PS_ARGS[@]}"
    status=$?
    set -e
    if [[ $status -eq 0 ]]; then
        rm -f "$TEMP_TXT"
        if [[ "$EMIT_TAG" == "true" ]]; then
            echo ""
            echo "[[audio_as_voice]]"
            echo "MEDIA:$OUTPUT"
        fi
        exit 0
    fi
    echo "Warning: DirectML inference failed (exit $status). Falling back to CPU in WSL." >&2
    VIBEVOICE_DEVICE="cpu"
fi

# Determine output format
OUTPUT_EXT="${OUTPUT##*.}"
TEMP_WAV=$(mktemp --suffix=.wav)

echo "Generating speech with VibeVoice..." >&2
echo "  Voice: $VOICE" >&2
echo "  Device: $VIBEVOICE_DEVICE" >&2
echo "  Text length: ${#TEXT} chars" >&2

# Run VibeVoice
cd "$VIBEVOICE_ROOT"
$PYTHON demo/realtime_model_inference_from_file.py \
    --model_path "$VIBEVOICE_CHECKPOINT" \
    --txt_path "$TEMP_TXT" \
    --speaker_name "$VOICE" \
    --output_dir "$(dirname "$TEMP_WAV")" \
    --device "$VIBEVOICE_DEVICE" \
    --cfg_scale "$VIBEVOICE_CFG_SCALE" \
    2>&1 | grep -v "^$" >&2

# Find the generated WAV file
GENERATED_WAV="$(dirname "$TEMP_WAV")/$(basename "$TEMP_TXT" .txt)_generated.wav"

if [[ ! -f "$GENERATED_WAV" ]]; then
    echo "Error: Generated WAV not found at $GENERATED_WAV" >&2
    rm -f "$TEMP_TXT"
    exit 1
fi

# Convert to output format
if [[ "$OUTPUT_EXT" == "ogg" ]]; then
    # Convert to OGG/Opus for WhatsApp voice note
    ffmpeg -y -i "$GENERATED_WAV" -c:a libopus -b:a 32k -ar 48000 -ac 1 -application voip "$OUTPUT" 2>/dev/null
elif [[ "$OUTPUT_EXT" == "mp3" ]]; then
    ffmpeg -y -i "$GENERATED_WAV" -c:a libmp3lame -b:a 64k "$OUTPUT" 2>/dev/null
else
    # Keep as WAV
    cp "$GENERATED_WAV" "$OUTPUT"
fi

# Cleanup
rm -f "$TEMP_TXT" "$GENERATED_WAV"

echo "Generated: $OUTPUT" >&2

# Emit Clawdbot tag if requested
if [[ "$EMIT_TAG" == "true" ]]; then
    echo ""
    echo "[[audio_as_voice]]"
    echo "MEDIA:$OUTPUT"
fi
