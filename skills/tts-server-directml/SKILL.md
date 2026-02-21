---
name: tts-server-directml
description: Universal TTS server for Windows with DirectML GPU acceleration (AMD/Intel/NVIDIA)
metadata: {"openclaw":{"emoji":"🔊","requires":{"bins":["powershell.exe"]}}}
---

# Universal TTS Server (DirectML)

A Windows-native TTS server that uses **DirectML** for GPU acceleration on AMD, Intel, and NVIDIA GPUs.

## Supported Models

| Model | Size | Quality | Speed | Languages |
|-------|------|---------|-------|-----------|
| **Qwen3-TTS** | 0.6B-1.7B | Excellent | Medium | 10 languages |
| **Piper** | 20-80MB | Good | Very Fast | 30+ languages |
| **Kokoro** | 82M params | Excellent | Fast | EN, JA, KO, ZH |
| **Edge TTS** | API | Good | Instant | 100+ voices |
| **XTTS v2** | 1.5GB | Excellent | Slow | 17 languages |

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Windows Native                           │
│  ┌─────────────────────────────────────────────────────┐    │
│  │           TTS Server (Python + DirectML)             │    │
│  │                                                      │    │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌────────┐ │    │
│  │  │ Qwen3-TTS│ │  Piper   │ │  Kokoro  │ │Edge TTS│ │    │
│  │  └──────────┘ └──────────┘ └──────────┘ └────────┘ │    │
│  │                      ▲                              │    │
│  │                      │ DirectML                     │    │
│  │              ┌───────┴───────┐                      │    │
│  │              │  AMD RX 6800  │                      │    │
│  │              └───────────────┘                      │    │
│  └─────────────────────────────────────────────────────┘    │
│                          ▲                                   │
│                          │ HTTP :8099                        │
└──────────────────────────┼──────────────────────────────────┘
                           │
┌──────────────────────────┼──────────────────────────────────┐
│         WSL2             │                                   │
│  ┌───────────────────────▼─────────────────────────────┐    │
│  │              OpenClaw / Client Scripts               │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

## Quick Start

### 1. Setup (Windows CMD or PowerShell)

```bash
# Navigate to skill directory
cd D:\Projects\raaz\skills\tts-server-directml

# Create venv and install
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
```

### 2. Start Server (Windows)

```bash
# From the skill directory with venv activated
python scripts/server.py

# Or with options:
TTS_DEFAULT_MODEL=kokoro TTS_PORT=8099 python scripts/server.py
```

### 2a. Start Server (Windows PowerShell helper)

```powershell
.\scripts\start-server.ps1 -Device directml -DefaultModel piper -Port 8099
```

### 2b. Start Server in Background (recommended)

```powershell
.\scripts\start-server-bg.ps1 -Device directml -DefaultModel piper -Port 8099
```

### Sync a local Piper voice (WSL -> Windows)

```powershell
.\scripts\sync-piper-voice.ps1 -ModelPath "C:\path\voice.onnx" -ConfigPath "C:\path\voice.onnx.json"
```

### 3. Test from WSL2

```bash
curl -X POST http://localhost:8099/tts \
  -H "Content-Type: application/json" \
  -d '{"text": "Hello world", "model": "piper"}' \
  --output test.ogg
```

## API Endpoints

### POST /tts
Generate speech from text.

**Request:**
```json
{
  "text": "Hello, world!",
  "model": "piper",           // qwen3, piper, kokoro, edge, xtts
  "voice": "en_US-amy-medium", // model-specific voice ID
  "language": "en",
  "speed": 1.0,
  "format": "ogg",            // wav, mp3, ogg
  "fast": true                // qwen3 only: enable fast generation
}
```

**Response:**
- `Content-Type: audio/ogg` (or wav/mp3)
- Binary audio data

### GET /models
List available models and their status.

### GET /voices/{model}
List available voices for a model.

### GET /health
Health check endpoint.

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `TTS_HOST` | `0.0.0.0` | Server bind address |
| `TTS_PORT` | `8099` | Server port |
| `TTS_DEFAULT_MODEL` | `piper` | Default model when not specified |
| `TTS_MODELS_DIR` | `~/.cache/tts-models` | Model cache directory |
| `TTS_DEVICE` | `directml` | Device: directml, cuda, cpu |

### Qwen3 Fast Mode (optional)

| Variable | Default | Description |
|----------|---------|-------------|
| `QWEN3_TTS_FAST` | off | Enable fast mode server-wide |
| `QWEN3_TTS_FAST_MAX_NEW_TOKENS` | 1024 | Cap output tokens in fast mode |
| `QWEN3_TTS_FAST_TOP_K` | 50 | Sampling top-k in fast mode |
| `QWEN3_TTS_FAST_TOP_P` | 0.95 | Sampling top-p in fast mode |
| `QWEN3_TTS_FAST_TEMPERATURE` | 1.0 | Sampling temperature in fast mode |
| `QWEN3_TTS_FAST_NO_SAMPLE` | off | Disable sampling (deterministic) |

## Model-Specific Configuration

### Qwen3-TTS
```json
{
  "model": "qwen3",
  "voice": "default",
  "instruct": "Speak cheerfully with an American accent",
  "language": "English",
  "fast": true
}
```

Qwen3 fast mode can also be enabled per request from WSL:

```bash
./scripts/tts-client.sh --text "Quick test" --model qwen3 --fast --out /tmp/tts.ogg
```

### Piper
```json
{
  "model": "piper",
  "voice": "en_US-amy-medium",  // See https://rhasspy.github.io/piper-samples/
  "speed": 1.0
}
```

### Kokoro
```json
{
  "model": "kokoro",
  "voice": "af_bella",  // af_*, am_*, bf_*, bm_*
  "language": "en-us"
}
```

### Edge TTS (Microsoft)
```json
{
  "model": "edge",
  "voice": "en-US-AriaNeural",
  "rate": "+0%",
  "pitch": "+0Hz"
}
```

## OpenClaw Integration

Add to `~/.openclaw/openclaw.json`:

```json
{
  "audio": {
    "reply": {
      "provider": "command",
      "command": [
        "/home/shkas/projects/raaz/skills/tts-server-directml/scripts/tts-client.sh",
        "--text-file", "{{ReplyTextFile}}",
        "--out", "{{ReplyAudioPath}}",
        "--model", "piper",
        "--emit-tag"
      ],
      "triggerOnVoice": true,
      "timeoutSeconds": 60
    }
  }
}
```

### Model Options for OpenClaw

| Model | Speed | Quality | Best For |
|-------|-------|---------|----------|
| `piper` | Very Fast | Good | Daily use, quick replies |
| `kokoro` | Fast | Excellent | High quality responses |
| `edge` | Instant | Good | When GPU unavailable |
| `qwen3` | Medium | Best | Important messages |
```

## Troubleshooting

### DirectML not detecting GPU
```powershell
# Check DirectML devices
python -c "import torch_directml; print(torch_directml.device_count())"
```

### Verify GPU + server devices
```powershell
.\scripts\verify-gpu.ps1
```

### Autostart (Task Scheduler)
```powershell
# Register to start at user logon
.\scripts\install-autostart.ps1 -Device directml -DefaultModel piper -Port 8099 -StartNow

# Remove autostart
.\scripts\uninstall-autostart.ps1
```

### Autostart with OpenClaw (WSL)
If you want warm servers to start **when you launch OpenClaw**, use the wrapper. It starts:
- DirectML TTS (this skill)
- Whisper warm server (voice-to-text-local)
- Embeddings server + proxy (embeddings-directml)

```bash
/home/shkas/projects/raaz/skills/tts-server-directml/scripts/openclaw-with-tts.sh
```

Optional: make it your default `openclaw` command in `~/.bashrc`:

```bash
alias openclaw="/home/shkas/projects/raaz/skills/tts-server-directml/scripts/openclaw-with-tts.sh"
```

You can disable Whisper autostart if needed:

```bash
WHISPER_AUTOSTART=0 /home/shkas/projects/raaz/skills/tts-server-directml/scripts/openclaw-with-tts.sh
```

You can disable embeddings autostart if needed:

```bash
EMBEDDINGS_AUTOSTART=0 /home/shkas/projects/raaz/skills/tts-server-directml/scripts/openclaw-with-tts.sh
```

You can skip embedding warm-up if you want a faster startup:

```bash
EMBEDDINGS_WARM=0 /home/shkas/projects/raaz/skills/tts-server-directml/scripts/openclaw-with-tts.sh
```

When using the wrapper, `openclaw gateway stop` will also stop the warm servers.
You can stop them manually with:

```bash
/home/shkas/projects/raaz/skills/tts-server-directml/scripts/stop-warm-servers.sh
```

### Model download fails
```powershell
# Manual download for Piper
Invoke-WebRequest -Uri "https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/amy/medium/en_US-amy-medium.onnx" -OutFile "$env:USERPROFILE\.cache\tts-models\piper\en_US-amy-medium.onnx"
```

### Server won't start
Check logs at: `%USERPROFILE%\.cache\tts-server\server.log`
