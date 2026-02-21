#!/bin/bash
#
# Qwen3-TTS Warm Mode Server
# Keeps model loaded in memory for fast voice note generation
#
# Usage:
#   server-start.sh    - Start the warm server
#   server-stop.sh     - Stop the warm server
#   server-status.sh   - Check if server is running
#
# The server runs on http://127.0.0.1:8099 by default
#
# First voice note request will trigger automatic startup
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_PYTHON="${HOME}/venv/qwen3-tts/bin/python"
SERVER_PID_FILE="${HOME}/.openclaw/qwen3-tts/server.pid"
SERVER_LOG_FILE="${HOME}/.openclaw/qwen3-tts/server.log"
SERVER_HOST="${QWEN3_TTS_HOST:-127.0.0.1}"
SERVER_PORT="${QWEN3_TTS_PORT:-8099}"
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

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

start_server() {
    echo "Starting Qwen3-TTS warm server..."
    echo "  Model: $MODEL"
    echo "  Host: $SERVER_HOST:$SERVER_PORT"
    
    # Create directory for PID file
    mkdir -p "$(dirname "$SERVER_PID_FILE")"
    
    # Check if already running
    if [[ -f "$SERVER_PID_FILE" ]]; then
        OLD_PID=$(cat "$SERVER_PID_FILE")
        if ps -p "$OLD_PID" > /dev/null 2>&1; then
            echo -e "${YELLOW}Server already running (PID: $OLD_PID)${NC}"
            return 0
        else
            rm -f "$SERVER_PID_FILE"
        fi
    fi
    
    # Start server in background (using Python 3.12 venv for onnxruntime compatibility)
    MODEL_ID="$MODEL" HOST="$SERVER_HOST" PORT="$SERVER_PORT" \
        QWEN3_TTS_DEVICE="${QWEN3_TTS_DEVICE:-auto}" QWEN3_TTS_LOCAL_ONLY="${QWEN3_TTS_LOCAL_ONLY:-}" \
        "$VENV_PYTHON" << 'PYTHON_SERVER' >> "$SERVER_LOG_FILE" 2>&1 &
import os
import sys
import torch
import uvicorn
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import soundfile as sf
import subprocess
import tempfile

app = FastAPI()

# Load VoiceDesign model
MODEL_ID = os.environ.get('MODEL_ID', 'Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign')
DEFAULT_INSTRUCT = "Speak with a cheerful American accent in a robotic, futuristic tone."

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

local_only = os.environ.get("QWEN3_TTS_LOCAL_ONLY", "").lower() in ("1", "true", "yes")
if os.path.isdir(MODEL_ID):
    local_only = True
if local_only:
    os.environ.setdefault("HF_HUB_OFFLINE", "1")

print(f"Loading model: {MODEL_ID}", flush=True)
try:
    from qwen_tts import Qwen3TTSModel
    device_kind = "cpu"
    device = torch.device("cpu")
    def resolve_device():
        requested = os.environ.get("QWEN3_TTS_DEVICE", "auto").lower()
        if requested in ("directml", "dml", "auto"):
            try:
                import torch_directml
                if torch_directml.device_count() > 0:
                    return "directml", torch_directml.device(0)
            except Exception as e:
                print(f"DirectML not available: {e}", flush=True)
        if requested in ("cuda", "auto") and torch.cuda.is_available():
            return "cuda", torch.device("cuda:0")
        return "cpu", torch.device("cpu")

    device_kind, device = resolve_device()
    print(f"Using device: {device_kind}", flush=True)
    dtype = torch.float32 if device_kind == "directml" else (torch.float16 if device_kind == "cuda" else torch.float32)
    attn_impl = os.environ.get("QWEN3_TTS_ATTN", "eager" if device_kind == "directml" else "auto")
    try:
        load_kwargs = {
            "dtype": dtype,
            "local_files_only": local_only,
        }
        if attn_impl and attn_impl != "auto":
            load_kwargs["attn_implementation"] = attn_impl
        model = Qwen3TTSModel.from_pretrained(MODEL_ID, **load_kwargs)
    except Exception as e:
        if dtype == torch.float16:
            print(f"Retrying model load in fp32: {e}", flush=True)
            load_kwargs = {
                "dtype": torch.float32,
                "local_files_only": local_only,
            }
            if attn_impl and attn_impl != "auto":
                load_kwargs["attn_implementation"] = attn_impl
            model = Qwen3TTSModel.from_pretrained(MODEL_ID, **load_kwargs)
        else:
            raise
    if device_kind != "cpu":
        try:
            model.model.to(device)
            model.device = device
        except Exception as e:
            print(f"Failed to move model to {device_kind}, using CPU: {e}", flush=True)
            device_kind = "cpu"
            model.model.to(torch.device("cpu"))
            model.device = torch.device("cpu")
    print(f"Model loaded successfully!", flush=True)
except Exception as e:
    print(f"Error loading model: {e}", flush=True)
    import traceback
    traceback.print_exc()
    sys.exit(1)

class TTSRequest(BaseModel):
    text: str
    instruct: str = DEFAULT_INSTRUCT
    language: str = "English"
    speed: float = 1.0
    top_k: int = 50
    top_p: float = 0.95
    temperature: float = 1.0

@app.get("/health")
async def health():
    return {
        "status": "ok",
        "model": MODEL_ID,
        "device": device_kind
    }

@app.post("/tts")
async def tts(request: TTSRequest):
    try:
        print(f"Generating: {request.text[:50]}... instruct={request.instruct[:30]}...", flush=True)
        language = language_map.get(request.language.strip().lower(), request.language)
        use_cache = device_kind != "directml"
        repetition_penalty = 1.0 if device_kind == "directml" else 1.05

        # Generate using VoiceDesign API
        wavs, sr = model.generate_voice_design(
            text=request.text,
            instruct=request.instruct,
            language=language,
            do_sample=True,
            top_k=request.top_k,
            top_p=request.top_p,
            temperature=request.temperature,
            max_new_tokens=2048,
            use_cache=use_cache,
            repetition_penalty=repetition_penalty
        )

        # Save as WAV
        with tempfile.NamedTemporaryFile(suffix='.wav', delete=False) as wav_file:
            sf.write(wav_file.name, wavs[0], sr)
            wav_path = wav_file.name

        # Convert to OGG
        ogg_path = wav_path.replace('.wav', '.ogg')
        subprocess.run([
            'ffmpeg', '-y', '-i', wav_path,
            '-c:a', 'libopus', '-b:a', '32k',
            '-vbr', 'on', '-ac', '1', ogg_path
        ], check=True, capture_output=True)

        # Read and return
        with open(ogg_path, 'rb') as f:
            audio_data = f.read()

        # Cleanup
        os.remove(wav_path)
        os.remove(ogg_path)

        print(f"Generated {len(audio_data)} bytes", flush=True)
        return {"audio": audio_data.hex(), "sample_rate": sr}

    except Exception as e:
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    HOST = os.environ.get('HOST', '127.0.0.1')
    PORT = int(os.environ.get('PORT', 8099))
    uvicorn.run(app, host=HOST, port=PORT)
PYTHON_SERVER
    
    SERVER_PID=$!
    echo $SERVER_PID > "$SERVER_PID_FILE"
    
    # Wait for server to start
    echo "Waiting for server to start..."
    sleep 5
    
    # Check if running
    if ps -p "$SERVER_PID" > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Qwen3-TTS warm server started (PID: $SERVER_PID)${NC}"
        echo "  API endpoint: http://$SERVER_HOST:$SERVER_PORT/tts"
    else
        echo -e "${RED}❌ Failed to start server${NC}"
        rm -f "$SERVER_PID_FILE"
        exit 1
    fi
}

stop_server() {
    echo "Stopping Qwen3-TTS warm server..."
    
    if [[ -f "$SERVER_PID_FILE" ]]; then
        PID=$(cat "$SERVER_PID_FILE")
        if ps -p "$PID" > /dev/null 2>&1; then
            kill "$PID" 2>/dev/null
            sleep 2
            # Force kill if still running
            if ps -p "$PID" > /dev/null 2>&1; then
                kill -9 "$PID" 2>/dev/null
            fi
            echo -e "${GREEN}✅ Server stopped${NC}"
        else
            echo -e "${YELLOW}Server was not running${NC}"
        fi
        rm -f "$SERVER_PID_FILE"
    else
        # Try to find by process name
        PIDS=$(pgrep -f "qwen3-tts" || true)
        if [[ -n "$PIDS" ]]; then
            echo "Found processes: $PIDS"
            kill $PIDS 2>/dev/null
            echo -e "${GREEN}✅ Server stopped${NC}"
        else
            echo -e "${YELLOW}No running server found${NC}"
        fi
    fi
}

status_server() {
    echo "Qwen3-TTS Warm Server Status"
    echo "============================"
    
    if [[ -f "$SERVER_PID_FILE" ]]; then
        PID=$(cat "$SERVER_PID_FILE")
        if ps -p "$PID" > /dev/null 2>&1; then
            echo -e "${GREEN}🟢 Running (PID: $PID)${NC}"
            echo "  API: http://$SERVER_HOST:$SERVER_PORT/tts"
            echo "  Model: $MODEL"
        else
            echo -e "${YELLOW}🟡 Not running (stale PID file)${NC}"
            rm -f "$SERVER_PID_FILE"
        fi
    else
        echo -e "${RED}🔴 Not running${NC}"
        echo ""
        echo "To start: $0 start"
    fi
}

case "${1:-start}" in
    start)
        start_server
        ;;
    stop)
        stop_server
        ;;
    status)
        status_server
        ;;
    restart)
        stop_server
        sleep 2
        start_server
        ;;
    *)
        echo "Usage: $0 {start|stop|status|restart}"
        exit 1
        ;;
esac
