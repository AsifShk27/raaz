#!/bin/bash
#
# Chroma 1.0 - Speech-to-Speech Chat
# Talk to it, get voice responses back
#
# Usage:
#   chroma-chat.sh --audio input.ogg --out response.ogg
#   chroma-chat.sh --audio input.ogg --voice-ref ref.wav --out response.ogg
#   chroma-chat.sh --text "Hello" --out response.ogg
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
COMMON_DEVICE="$SKILLS_ROOT/_common/device.sh"
if [[ -f "$COMMON_DEVICE" ]]; then
    # shellcheck source=/dev/null
    source "$COMMON_DEVICE"
fi
VENV_PYTHON="${HOME}/venv/chroma-voice/bin/python"
MODEL_ID="${CHROMA_MODEL:-FlashLabs/Chroma-4B}"
DEVICE="${CHROMA_DEVICE:-${OPENCLAW_DEVICE:-}}"
if [[ -z "$DEVICE" && "$(type -t openclaw_device_default || true)" == "function" ]]; then
    DEVICE="$(openclaw_device_default)"
fi
[[ -z "$DEVICE" ]] && DEVICE="auto"

# Defaults
AUDIO_INPUT=""
TEXT_INPUT=""
VOICE_REF=""
VOICE_TEXT=""
OUTPUT_FILE=""
SYSTEM_PROMPT="You are Chroma, a helpful voice assistant. Respond naturally and conversationally."

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --audio)
            AUDIO_INPUT="$2"
            shift 2
            ;;
        --text)
            TEXT_INPUT="$2"
            shift 2
            ;;
        --voice-ref)
            VOICE_REF="$2"
            shift 2
            ;;
        --voice-text)
            VOICE_TEXT="$2"
            shift 2
            ;;
        --out)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --system)
            SYSTEM_PROMPT="$2"
            shift 2
            ;;
        --help|-h)
            echo "Chroma 1.0 - Speech-to-Speech Chat"
            echo ""
            echo "Usage:"
            echo "  $0 --audio input.ogg --out response.ogg"
            echo "  $0 --text \"Hello\" --out response.ogg"
            echo ""
            echo "Options:"
            echo "  --audio      Input audio file"
            echo "  --text       Input text (if no audio)"
            echo "  --voice-ref  Reference audio for voice cloning"
            echo "  --voice-text Text spoken in reference audio"
            echo "  --out        Output audio file"
            echo "  --system     Custom system prompt"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}" >&2
            exit 1
            ;;
    esac
done

# Validate
if [[ -z "$AUDIO_INPUT" && -z "$TEXT_INPUT" ]]; then
    echo -e "${RED}Error: Provide --audio or --text${NC}" >&2
    exit 1
fi

if [[ -z "$OUTPUT_FILE" ]]; then
    OUTPUT_FILE="/tmp/chroma-response-$(date +%s).ogg"
fi

# Check venv
if [[ ! -f "$VENV_PYTHON" ]]; then
    echo -e "${RED}Error: Chroma venv not found at $VENV_PYTHON${NC}" >&2
    echo "Run: python3.12 -m venv ~/venv/chroma-voice" >&2
    exit 1
fi

# DirectML path (Windows)
if [[ "${DEVICE,,}" == "directml" || "${DEVICE,,}" == "dml" ]]; then
    if ! command -v powershell.exe >/dev/null 2>&1; then
        echo -e "${RED}Error: powershell.exe not found. DirectML path requires Windows PowerShell.${NC}" >&2
        exit 1
    fi
    PS_SCRIPT="${SCRIPT_DIR}/chroma-chat-directml.ps1"
    if [[ ! -f "$PS_SCRIPT" ]]; then
        echo -e "${RED}Error: Missing PowerShell script: $PS_SCRIPT${NC}" >&2
        exit 1
    fi
    PS_SCRIPT_WIN="$(wslpath -w "$PS_SCRIPT")"

    PS_ARGS=(-NoProfile -ExecutionPolicy Bypass -File "$PS_SCRIPT_WIN" -Model "$MODEL_ID" -SystemPrompt "$SYSTEM_PROMPT")
    if [[ -n "$AUDIO_INPUT" ]]; then
        PS_ARGS+=(-Audio "$(wslpath -w "$AUDIO_INPUT")")
    fi
    if [[ -n "$TEXT_INPUT" ]]; then
        PS_ARGS+=(-Text "$TEXT_INPUT")
    fi
    if [[ -n "$VOICE_REF" ]]; then
        PS_ARGS+=(-VoiceRef "$(wslpath -w "$VOICE_REF")")
    fi
    if [[ -n "$VOICE_TEXT" ]]; then
        PS_ARGS+=(-VoiceText "$VOICE_TEXT")
    fi
    PS_ARGS+=(-Out "$(wslpath -w "$OUTPUT_FILE")")
    if [[ -n "${OPENCLAW_WIN_PYTHON:-}" ]]; then
        PS_ARGS+=(-PythonPath "${OPENCLAW_WIN_PYTHON}")
    fi

    powershell.exe "${PS_ARGS[@]}"
    exit $?
fi

echo -e "${YELLOW}Generating response with Chroma...${NC}" >&2

# Run inference
CHROMA_DEVICE="$DEVICE" "$VENV_PYTHON" << PYTHON_SCRIPT
import os
import sys
import torch
import soundfile as sf
import subprocess

# Settings
model_id = "$MODEL_ID"
audio_input = "$AUDIO_INPUT" or None
text_input = "$TEXT_INPUT" or None
voice_ref = "$VOICE_REF" or None
voice_text = "$VOICE_TEXT" or None
output_file = "$OUTPUT_FILE"
system_prompt = """$SYSTEM_PROMPT"""

device_req = os.environ.get("CHROMA_DEVICE", "auto").lower()
device_kind = "cpu"
device = torch.device("cpu")
if device_req in ("directml", "dml"):
    try:
        import torch_directml
        if torch_directml.device_count() > 0:
            device_kind = "directml"
            device = torch_directml.device(0)
    except Exception as e:
        print(f"DirectML not available: {e}", file=sys.stderr)
elif device_req in ("cuda", "auto") and torch.cuda.is_available():
    device_kind = "cuda"
    device = torch.device("cuda:0")

print(f"Loading Chroma model: {model_id} on {device_kind}", file=sys.stderr)

try:
    from transformers import AutoModelForCausalLM, AutoProcessor

    dtype = torch.float16 if device_kind in ("cuda", "directml") else torch.float32
    try:
        model = AutoModelForCausalLM.from_pretrained(
            model_id,
            trust_remote_code=True,
            device_map="cpu",
            torch_dtype=dtype
        )
    except Exception as e:
        if dtype == torch.float16:
            print(f"Retrying model load in fp32: {e}", file=sys.stderr)
            model = AutoModelForCausalLM.from_pretrained(
                model_id,
                trust_remote_code=True,
                device_map="cpu",
                torch_dtype=torch.float32
            )
        else:
            raise
    if device_kind != "cpu":
        try:
            model = model.to(device)
        except Exception as e:
            print(f"Failed to move model to {device_kind}, using CPU: {e}", file=sys.stderr)
            device_kind = "cpu"
            device = torch.device("cpu")
            model = model.to(device)
    processor = AutoProcessor.from_pretrained(model_id, trust_remote_code=True)
    print("Model loaded!", file=sys.stderr)
except Exception as e:
    print(f"Error loading model: {e}", file=sys.stderr)
    sys.exit(1)

# Build conversation
conversation = [[
    {
        "role": "system",
        "content": [{"type": "text", "text": system_prompt}],
    },
    {
        "role": "user",
        "content": [],
    },
]]

# Add input (audio or text)
if audio_input:
    conversation[0][1]["content"].append({"type": "audio", "audio": audio_input})
elif text_input:
    conversation[0][1]["content"].append({"type": "text", "text": text_input})

# Process with optional voice cloning
prompt_audio = [voice_ref] if voice_ref else None
prompt_text = [voice_text] if voice_text else None

print("Processing inputs...", file=sys.stderr)
inputs = processor(
    conversation,
    add_generation_prompt=True,
    tokenize=False,
    prompt_audio=prompt_audio,
    prompt_text=prompt_text
)

# Move to device
inputs = {k: v.to(device) if hasattr(v, 'to') else v for k, v in inputs.items()}

# Generate
print("Generating response...", file=sys.stderr)
with torch.no_grad():
    output = model.generate(
        **inputs,
        max_new_tokens=200,
        do_sample=True,
        temperature=0.7,
        top_p=0.9,
        use_cache=True
    )

# Decode audio
print("Decoding audio...", file=sys.stderr)
audio_values = model.codec_model.decode(output.permute(0, 2, 1)).audio_values
audio_np = audio_values[0].cpu().detach().numpy()

# Save as WAV first
wav_path = output_file.replace('.ogg', '.wav')
sf.write(wav_path, audio_np, 24000)

# Convert to OGG
subprocess.run([
    'ffmpeg', '-y', '-i', wav_path,
    '-c:a', 'libopus', '-b:a', '48k',
    '-vbr', 'on', '-ac', '1',
    output_file
], check=True, capture_output=True)

os.remove(wav_path)
print(f"Saved: {output_file}", file=sys.stderr)
PYTHON_SCRIPT

if [[ -f "$OUTPUT_FILE" ]]; then
    echo -e "${GREEN}✅ Response saved: $OUTPUT_FILE${NC}" >&2
else
    echo -e "${RED}❌ Failed to generate response${NC}" >&2
    exit 1
fi
