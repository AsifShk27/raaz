---
name: qwen3-tts
description: AUTO-CONFIGURED - Do NOT manually invoke. Just reply with text, system converts to voice automatically.
metadata: {"openclaw":{"emoji":"🎤","requires":{"bins":["python3","ffmpeg"]},"install":[{"id":"pip","kind":"pip","packages":["transformers","torch"],"label":"Install Qwen3-TTS dependencies"}]}}
---

# ⛔ STOP - READ THIS FIRST

**DO NOT RUN ANY SCRIPTS FROM THIS SKILL FOR CHAT REPLIES.**

Qwen3-TTS is configured as the system's auto-reply TTS. When you reply with TEXT, the system AUTOMATICALLY converts it to voice.

**YOUR ONLY JOB:** Reply with plain text. Nothing else. No exec, no scripts, no manual TTS.

---

# Qwen3-TTS (On-Prem Voice Replies)

This skill adds a **local/offline** TTS pipeline for OpenClaw voice-note replies using **Qwen3-TTS** (Alibaba) and `ffmpeg`.

---

## What is Qwen3-TTS?

Released Jan 21, 2026 by Alibaba Cloud, Qwen3-TTS is a state-of-the-art open-source TTS system featuring:
- **5 models**: 0.6B & 1.8B parameter sizes
- **Voice Design & Cloning**: Free-form, no reference audio needed
- **10 language support**: English, Chinese, Spanish, French, German, Portuguese, Vietnamese, Malayalam, Bengali, Tamil
- **12Hz tokenizer**: Superior compression & quality
- **SOTA performance**: Arguably the most disruptive open-source TTS release

**Official Links:**
- GitHub: github.com/QwenLM/Qwen3-TTS
- HF: huggingface.co/collections/Qwen/qwen3-tts
- Paper: github.com/QwenLM/Qwen3-TTS/blob/main/assets/Qwen3_TTS.pdf

---

## ⚠️ CRITICAL: DO NOT MANUALLY INVOKE TTS FOR CHAT REPLIES

**Qwen3-TTS is NOW the configured auto-reply TTS.** The system automatically converts ALL text replies to voice.

### What YOU (the agent) must do:

1. **ONLY reply with plain text** - the system handles voice conversion
2. **NEVER run TTS scripts manually** for chat replies
3. **NEVER send both voice AND text** - this causes duplicate messages

### What happens automatically:

- User sends voice message → You reply with TEXT → System converts to voice via Qwen3-TTS
- This is already configured in `~/.openclaw/openclaw.json` → `audio.reply.command`

### When to use scripts directly:

- **ONLY** for non-chat purposes (e.g., generating audio files, testing)
- **NEVER** for responding to user messages in chat

---

## Prerequisites

### Python Version Requirement

**Qwen3-TTS requires Python 3.12** because `onnxruntime` is not available for Python 3.14 yet.

**✅ CONFIGURED**: A Python 3.12 virtual environment is set up at `~/venv/qwen3-tts/` and the scripts automatically use it.

### Virtual Environment Details

```
Location: ~/venv/qwen3-tts/
Python:   3.12.3
Status:   Ready to use
```

### Installed Dependencies

- torch, transformers, accelerate, safetensors
- onnxruntime, soundfile, numpy, scipy
- uvicorn, fastapi, pydantic (for warm server)

### Verify Installation

```bash
~/venv/qwen3-tts/bin/python -c "import torch, onnxruntime; print('Qwen3-TTS ready!')"
```

---

## Scripts

| Script | Description |
|--------|-------------|
| `voice-note-qwen3-tts.sh` | **PRIMARY** - Generates voice note from text |
| `voice-note-qwen3-tts-warm.sh` | Warm mode - keeps model loaded for fast responses |
| `server-start.sh` | Start warm server manually |
| `server-stop.sh` | Stop warm server |
| `server-status.sh` | Check server health |

---

## Environment Variables

### Required

| Variable | Description |
|----------|-------------|
| `QWEN3_TTS_MODEL` | Model ID or path (default: `Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign`) |

### Optional

| Variable | Default | Description |
|----------|---------|-------------|
| `QWEN3_TTS_SIZE` | `1.7B` | Model size (`0.6B` or `1.8B`) |
| `QWEN3_TTS_LANGUAGE` | `English` | Language name or code (`English`, `en`, `zh`, etc.) |
| `QWEN3_TTS_SPEED` | `1.0` | Speaking rate (0.5-2.0) |
| `QWEN3_TTS_TOP_K` | `50` | Sampling top-k |
| `QWEN3_TTS_TOP_P` | `0.95` | Sampling top-p |
| `QWEN3_TTS_TEMP` | `1.0` | Temperature |
| `QWEN3_TTS_MAX_CHARS` | `3000` | Max text length |
| `QWEN3_TTS_HOST` | `127.0.0.1` | Warm server host |
| `QWEN3_TTS_PORT` | `8099` | Warm server port |
| `QWEN3_TTS_DEVICE` | `auto` | Device: `auto`, `directml`, `cuda`, `cpu` (defaults to `directml` on WSL if PowerShell is available) |
| `QWEN3_TTS_MODEL_DIR` | unset | Local model directory (preferred when `QWEN3_TTS_MODEL` is unset and files exist) |
| `QWEN3_TTS_LOCAL_ONLY` | `0` | Set `1` to disable downloads and use local files only |
| `OPENCLAW_DEVICE` | unset | Global device hint used by multiple skills (`directml`, `cuda`, `cpu`, `auto`) |
| `OPENCLAW_WIN_PYTHON` | unset | Windows Python path for DirectML (e.g., `C:\\Python312\\python.exe`) |

### Language Codes (Names or ISO Codes)

| Code | Language |
|------|----------|
| `en` | English |
| `zh` | Chinese |
| `es` | Spanish |
| `fr` | French |
| `de` | German |
| `pt` | Portuguese |
| `vi` | Vietnamese |
| `ml` | Malayalam |
| `bn` | Bengali |
| `ta` | Tamil |

---

## Local Model Storage (No Downloads)

If you want to keep model files fully local, place them on disk and point `QWEN3_TTS_MODEL_DIR`
to the directory. When set, the scripts will prefer that path and will avoid downloads if
`QWEN3_TTS_LOCAL_ONLY=1`.

```bash
export QWEN3_TTS_MODEL_DIR="$HOME/.openclaw/qwen3-tts/models/Qwen3-TTS-12Hz-1.7B-VoiceDesign"
export QWEN3_TTS_LOCAL_ONLY=1
```

## Quick Test (Python 3.12 only)

```bash
# First run will download model (~3-4GB)
export MODEL_ID="Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign"

# Test with Python
python3 << 'PYTHON'
from qwen_tts import Qwen3TTSModel
import soundfile as sf
import torch

tts = Qwen3TTSModel.from_pretrained("Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign", device_map="cpu", torch_dtype=torch.float16)
tts.model.to("cuda")  # or use torch_directml.device(0) on Windows
tts.device = tts.model.device
wavs, sr = tts.generate_voice_design(
    text="Hello, this is Qwen3-TTS!",
    instruct="Speak with a cheerful American accent in a robotic, futuristic tone.",
    language="English"
)
sf.write("/tmp/test.wav", wavs[0], sr)
print("Test successful!")
PYTHON
```

---

## Warm Mode (Recommended)

Warm mode keeps the Qwen3-TTS model loaded in memory for fast responses.

### How it works

1. First voice reply triggers server startup
2. Server loads model once (~10-30GB RAM for 1.7B model)
3. Subsequent requests are fast (<2s synthesis)
4. Server runs on `http://127.0.0.1:8099` by default

### Server Management

```bash
# Check status
/home/shkas/projects/raaz/skills/qwen3-tts/scripts/server-status.sh

# Start manually (e.g., at boot)
/home/shkas/projects/raaz/skills/qwen3-tts/scripts/server-start.sh

# Stop server
/home/shkas/projects/raaz/skills/qwen3-tts/scripts/server-stop.sh
```

### Windows DirectML Warm Server

If you want Qwen3‑TTS to run on an AMD GPU (DirectML) from Windows, use:

```powershell
.\scripts\server-start.ps1 -Device directml -Model "Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign"
.\scripts\server-status.ps1
.\scripts\server-stop.ps1
```

When `QWEN3_TTS_DEVICE=directml`, the warm WSL script will auto‑start the Windows server and use it.
The warm server exposes `GET /health` for status checks. From WSL you can probe it at:
`curl http://$(openclaw_windows_host):8099/health`
If a WSL warm server was already running on port 8099, the warm script will stop it before starting DirectML
to avoid WSL port proxy collisions.

---

## Performance Comparison

| Mode | Model Load | Synthesis | Memory |
|------|-----------|-----------|--------|
| Warm (1.7B) | ~30s first | ~2s | ~15-20GB |
| Cold (1.7B) | ~30s each | ~30s | 0 when idle |
| Warm (0.6B) | ~10s first | ~1s | ~5-8GB |
| Cold (0.6B) | ~10s each | ~10s | 0 when idle |

---

## Custom Voice (Advanced)

Qwen3-TTS supports free-form voice design without reference audio!

```bash
# Generate with custom voice characteristics
export QWEN3_TTS_VOICE_STYLE="friendly,warm,clear"

# Or use VoiceDesign model for custom voice creation
export QWEN3_TTS_MODEL="Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign"

# See examples/test_model_12hz_voice_design.py in the repo
```

---

## Troubleshooting

### Model download fails
```bash
# Check Hugging Face login
huggingface-cli whoami

# Or manually download:
git lfs install
git clone https://huggingface.co/Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign ~/.cache/huggingface/hub/models--Qwen--Qwen3-TTS-12Hz-1.7B-VoiceDesign
```

### Out of memory (OOM)
- Use smaller model: `export QWEN3_TTS_SIZE="0.6B"`
- Or use cold mode instead of warm mode

### Module not found error
- Qwen3-TTS requires Python 3.12 (onnxruntime not available for 3.14)
- Use Piper TTS instead (works with Python 3.14)

### Slow synthesis
- Use warm mode (recommended)
- Use smaller model (0.6B) for faster output

---

## Configuration for OpenClaw

To use Qwen3-TTS as the default voice reply system:

```bash
# Update ~/.openclaw/openclaw.json
{
  "audio": {
    "reply": {
      "provider": "command",
      "command": [
        "/home/shkas/projects/raaz/skills/qwen3-tts/scripts/voice-note-qwen3-tts-warm.sh",
        "--text-file",
        "{{ReplyTextFile}}",
        "--out",
        "{{ReplyAudioPath}}"
      ],
      "triggerOnVoice": true,
      "timeoutSeconds": 120
    }
  }
}
```

**Note:** Requires Python 3.12 virtual environment. Piper TTS is recommended for systems with Python 3.14.

---

## Model Options

| Model ID | Size | Best For |
|----------|------|----------|
| `Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign` | 1.7B | Best quality, general use (instruction‑driven) |
| `Qwen/Qwen3-TTS-12Hz-1.7B-Base` | 1.7B | Voice‑clone only (requires reference audio) |
| `Qwen/Qwen3-TTS-12Hz-0.6B-Base` | 0.6B | Fast inference, low memory |
| `Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign` | 1.7B | Custom voice creation |
| `Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice` | 1.7B | Voice cloning |
| `Qwen/Qwen3-TTS-12Hz-0.6B-CustomVoice` | 0.6B | Lightweight voice cloning |

---

## References

- **Paper**: github.com/QwenLM/Qwen3-TTS/blob/main/assets/Qwen3_TTS.pdf
- **HF Models**: huggingface.co/collections/Qwen/qwen3-tts
- **Demo**: huggingface.co/spaces/Qwen/Qwen3-TTS
- **GitHub**: github.com/QwenLM/Qwen3-TTS
- **API**: help.alibabacloud.com/en/model-studio/qwen-tts-voice-design
