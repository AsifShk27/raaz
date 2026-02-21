#!/bin/bash
#
# Qwen3-TTS Voice Note Generator
# Generates OGG audio from text using Qwen3-TTS VoiceDesign model
#
# Usage:
#   voice-note-qwen3-tts.sh --text "Hello world" --out /tmp/reply.ogg
#   voice-note-qwen3-tts.sh --text-file /tmp/text.txt --out /tmp/reply.ogg
#   voice-note-qwen3-tts.sh --text "Hello" --emit-tag
#
# Options:
#   --text         Text to speak (required if no --text-file)
#   --text-file    Path to text file (required if no --text)
#   --out          Output OGG path (required unless --emit-tag)
#   --emit-tag     Print Clawdbot media tag (optional)
#   --model        Model ID (default: Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign)
#   --language     Language code (default: English)
#   --instruct     Voice style instruction (default: "Speak naturally")
#   --help         Show this help
#

set -e

# Default values
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
COMMON_DEVICE="$SKILLS_ROOT/_common/device.sh"
if [[ -f "$COMMON_DEVICE" ]]; then
    # shellcheck source=/dev/null
    source "$COMMON_DEVICE"
fi
VENV_PYTHON="${HOME}/venv/qwen3-tts/bin/python"
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
LANGUAGE="${QWEN3_TTS_LANGUAGE:-English}"
INSTRUCT="${QWEN3_TTS_INSTRUCT:-Speak with a cheerful American accent in a robotic, futuristic tone.}"
TOP_K="${QWEN3_TTS_TOP_K:-50}"
TOP_P="${QWEN3_TTS_TOP_P:-0.95}"
TEMP="${QWEN3_TTS_TEMP:-1.0}"
MAX_CHARS="${QWEN3_TTS_MAX_CHARS:-3000}"
OUTPUT_FILE=""
TEXT=""
EMIT_TAG=false
DEVICE="${QWEN3_TTS_DEVICE:-${OPENCLAW_DEVICE:-}}"
if [[ -z "$DEVICE" && "$(type -t openclaw_device_default || true)" == "function" ]]; then
    DEVICE="$(openclaw_device_default)"
fi
if [[ -z "$DEVICE" ]]; then
    DEVICE="auto"
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

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
                echo -e "${RED}Error: Text file not found: $2${NC}" >&2
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
        --model)
            MODEL="$2"
            shift 2
            ;;
        --language)
            LANGUAGE="$2"
            shift 2
            ;;
        --instruct)
            INSTRUCT="$2"
            shift 2
            ;;
        --help|-h)
            grep '^#' "$0" | sed 's/^#//' | head -25
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}" >&2
            exit 1
            ;;
    esac
done

# Validate inputs
if [[ -z "$TEXT" ]]; then
    echo -e "${RED}Error: No text provided. Use --text or --text-file${NC}" >&2
    exit 1
fi

if [[ "$EMIT_TAG" == "false" && -z "$OUTPUT_FILE" ]]; then
    echo -e "${RED}Error: No output file specified. Use --out${NC}" >&2
    exit 1
fi

# Truncate text if too long
if [[ ${#TEXT} -gt $MAX_CHARS ]]; then
    TEXT="${TEXT:0:$MAX_CHARS}"
    echo -e "${YELLOW}Warning: Text truncated to $MAX_CHARS characters${NC}" >&2
fi

# Output file
if [[ -z "$OUTPUT_FILE" ]]; then
    OUTPUT_FILE="/tmp/qwen3-tts-$(date +%s).ogg"
fi

# DirectML path (Windows)
if [[ "${DEVICE,,}" == "directml" || "${DEVICE,,}" == "dml" ]]; then
    if ! command -v powershell.exe >/dev/null 2>&1; then
        echo -e "${RED}Error: powershell.exe not found. DirectML path requires Windows PowerShell.${NC}" >&2
        exit 1
    fi
    PS_SCRIPT="${SCRIPT_DIR}/voice-note-qwen3-tts-directml.ps1"
    if [[ ! -f "$PS_SCRIPT" ]]; then
        echo -e "${RED}Error: Missing PowerShell script: $PS_SCRIPT${NC}" >&2
        exit 1
    fi
    PS_SCRIPT_WIN="$(wslpath -w "$PS_SCRIPT")"

    tmp_text="/tmp/qwen3-tts-text-$$.txt"
    echo -n "$TEXT" > "$tmp_text"
    win_text=$(wslpath -w "$tmp_text")
    win_out=$(wslpath -w "$OUTPUT_FILE")
    MODEL_WIN="$MODEL"
    if [[ -e "$MODEL" ]]; then
        MODEL_WIN="$(wslpath -w "$MODEL")"
    fi

    PS_ARGS=(
        -NoProfile -ExecutionPolicy Bypass -File "$PS_SCRIPT_WIN"
        -TextFile "$win_text" -Out "$win_out"
        -Model "$MODEL_WIN" -Language "$LANGUAGE" -Instruct "$INSTRUCT"
        -TopK "$TOP_K" -TopP "$TOP_P" -Temp "$TEMP" -MaxChars "$MAX_CHARS"
    )
    if [[ -n "${OPENCLAW_WIN_PYTHON:-}" ]]; then
        PS_ARGS+=(-PythonPath "${OPENCLAW_WIN_PYTHON}")
    fi
    powershell.exe "${PS_ARGS[@]}"

    rm -f "$tmp_text"

    if [[ -f "$OUTPUT_FILE" ]]; then
        echo -e "${GREEN}✅ Voice note generated: $OUTPUT_FILE${NC}" >&2
        if [[ "$EMIT_TAG" == "true" ]]; then
            echo "[[audio_as_voice]]"
            echo "MEDIA:$OUTPUT_FILE"
        fi
        exit 0
    fi

    echo -e "${RED}❌ Failed to generate voice note${NC}" >&2
    exit 1
fi

# Log file
LOG_FILE="${HOME}/.openclaw/qwen3-tts/generation.log"
mkdir -p "$(dirname "$LOG_FILE")"

echo "[$(date)] Generating voice note with Qwen3-TTS..." >> "$LOG_FILE"
echo "  Model: $MODEL" >> "$LOG_FILE"
echo "  Language: $LANGUAGE" >> "$LOG_FILE"
echo "  Instruct: $INSTRUCT" >> "$LOG_FILE"
echo "  Text length: ${#TEXT} chars" >> "$LOG_FILE"

# Generate audio using Python script
PYTHON_SCRIPT=$(cat << 'PYTHON_SCRIPT'
import os
import sys
import torch
import soundfile as sf
import subprocess
import json

os.environ.setdefault("TORCHAUDIO_USE_SOUNDFILE", "1")
os.environ.setdefault("TORCHAUDIO_BACKEND", "soundfile")
cache_root = os.path.join(os.path.expanduser("~"), ".cache", "huggingface")
os.environ.setdefault("HF_HOME", cache_root)
os.environ.setdefault("HUGGINGFACE_HUB_CACHE", os.path.join(cache_root, "hub"))
os.environ.setdefault("HF_HUB_DISABLE_SYMLINKS_WARNING", "1")
os.environ.setdefault("HF_HUB_DISABLE_XET", "1")
os.environ.setdefault("HF_HUB_DOWNLOAD_TIMEOUT", "300")
os.environ.setdefault("HF_HUB_DOWNLOAD_RETRY", "5")

# Settings from environment
model_id = os.environ.get('MODEL_ID', 'Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign')
text = sys.argv[1]
output_file = sys.argv[2]
language = os.environ.get('LANGUAGE', 'English')
instruct = os.environ.get('INSTRUCT', 'Speak in a friendly, natural tone.')
top_k = int(os.environ.get('TOP_K', '50'))
top_p = float(os.environ.get('TOP_P', '0.95'))
temp = float(os.environ.get('TEMP', '1.0'))

language_map = {
    "en": "English",
    "zh": "Chinese",
    "es": "Spanish",
    "fr": "French",
    "de": "German",
    "pt": "Portuguese",
    "vi": "Vietnamese",
    "ml": "Malayalam",
    "bn": "Bengali",
    "ta": "Tamil",
}
lang_key = language.strip().lower()
language = language_map.get(lang_key, language)

local_only = os.environ.get("QWEN3_TTS_LOCAL_ONLY", "").lower() in ("1", "true", "yes")
if os.path.isdir(model_id):
    local_only = True
if local_only:
    os.environ.setdefault("HF_HUB_OFFLINE", "1")

from qwen_tts import Qwen3TTSModel

def resolve_device():
    requested = os.environ.get("QWEN3_TTS_DEVICE", "auto").lower()
    if requested in ("directml", "dml", "auto"):
        try:
            import torch_directml
            if torch_directml.device_count() > 0:
                return "directml", torch_directml.device(0)
        except Exception as e:
            print(f"DirectML not available: {e}", file=sys.stderr)
    if requested in ("cuda", "auto") and torch.cuda.is_available():
        return "cuda", torch.device("cuda:0")
    return "cpu", torch.device("cpu")

device_kind, device = resolve_device()
print(f"Loading model: {model_id} on {device_kind}", file=sys.stderr)
try:
    dtype = torch.float32 if device_kind == "directml" else (torch.float16 if device_kind == "cuda" else torch.float32)
    attn_impl = os.environ.get("QWEN3_TTS_ATTN", "eager" if device_kind == "directml" else "auto")
    try:
        load_kwargs = {
            "dtype": dtype,
            "local_files_only": local_only,
        }
        if attn_impl and attn_impl != "auto":
            load_kwargs["attn_implementation"] = attn_impl
        model = Qwen3TTSModel.from_pretrained(model_id, **load_kwargs)
    except Exception as e:
        if dtype == torch.float16:
            print(f"Retrying model load in fp32: {e}", file=sys.stderr)
            load_kwargs = {
                "dtype": torch.float32,
                "local_files_only": local_only,
            }
            if attn_impl and attn_impl != "auto":
                load_kwargs["attn_implementation"] = attn_impl
            model = Qwen3TTSModel.from_pretrained(model_id, **load_kwargs)
        else:
            raise
    if device_kind != "cpu":
        try:
            model.model.to(device)
            model.device = device
        except Exception as e:
            print(f"Failed to move model to {device_kind}, using CPU: {e}", file=sys.stderr)
            device_kind = "cpu"
            model.model.to(torch.device("cpu"))
            model.device = torch.device("cpu")
    print(f"Model loaded successfully!", file=sys.stderr)
except Exception as e:
    print(f"Error loading model: {e}", file=sys.stderr)
    import traceback
    traceback.print_exc()
    sys.exit(1)

# Generate audio using VoiceDesign API
print(f"Generating audio...", file=sys.stderr)
try:
    wavs, sr = model.generate_voice_design(
        text=text,
        instruct=instruct,
        language=language,
        do_sample=True,
        top_k=top_k,
        top_p=top_p,
        temperature=temp,
        max_new_tokens=2048,
        use_cache=(device_kind != "directml"),
        repetition_penalty=(1.0 if device_kind == "directml" else 1.05)
    )
    print(f"Generation complete! Samples: {len(wavs)}, SR: {sr}", file=sys.stderr)
except Exception as e:
    print(f"Error generating audio: {e}", file=sys.stderr)
    import traceback
    traceback.print_exc()
    sys.exit(1)

# Save as WAV first (then convert to OGG)
wav_file = output_file.replace('.ogg', '.wav')
sf.write(wav_file, wavs[0], sr)

# Convert to OGG using ffmpeg (WhatsApp compatible)
print(f"Converting to OGG...", file=sys.stderr)
subprocess.run([
    'ffmpeg', '-y', '-i', wav_file,
    '-c:a', 'libopus', '-b:a', '32k',
    '-vbr', 'on', '-ac', '1',  # Mono for smaller size
    output_file
], check=True, capture_output=True)

# Cleanup
os.remove(wav_file)

print(f"Audio saved to: {output_file}", file=sys.stderr)
print(json.dumps({"success": True, "output": output_file}), file=sys.stdout)
PYTHON_SCRIPT
)

# Run the Python script
generator_script="$(mktemp /tmp/qwen3-tts-generator-XXXXXX.py)"
echo "$PYTHON_SCRIPT" > "$generator_script"

cd /tmp
MODEL_ID="$MODEL" LANGUAGE="$LANGUAGE" INSTRUCT="$INSTRUCT" \
    TOP_K="$TOP_K" TOP_P="$TOP_P" TEMP="$TEMP" \
    QWEN3_TTS_DEVICE="$DEVICE" QWEN3_TTS_LOCAL_ONLY="${QWEN3_TTS_LOCAL_ONLY:-}" \
    "$VENV_PYTHON" "$generator_script" "$TEXT" "$OUTPUT_FILE" 2>> "$LOG_FILE"

# Check result
if [[ -f "$OUTPUT_FILE" ]]; then
    echo -e "${GREEN}✅ Voice note generated: $OUTPUT_FILE${NC}" >&2
    
    if [[ "$EMIT_TAG" == "true" ]]; then
        echo "[[audio_as_voice]]"
        echo "MEDIA:$OUTPUT_FILE"
    fi
    
    # Clean up Python script
    rm -f "$generator_script"
    
    exit 0
else
    echo -e "${RED}❌ Failed to generate voice note${NC}" >&2
    rm -f "$generator_script"
    exit 1
fi
