---
name: chroma-voice
description: Real-time speech-to-speech AI with voice cloning using Chroma 1.0 by FlashLabs. Talk to it, it responds with voice.
status: experimental
---

# Chroma 1.0 - Speech-to-Speech Voice Agent

Chroma is an **end-to-end speech-to-speech** model by FlashLabs. Unlike TTS (text-to-speech), Chroma:
- Directly understands audio input (no ASR needed)
- Reasons about the conversation
- Generates audio responses
- Can clone voices from a few seconds of reference audio

**Released:** January 2026
**License:** Apache 2.0

---

## Links

- Paper: https://arxiv.org/abs/2601.11141
- HuggingFace: https://huggingface.co/FlashLabs/Chroma-4B
- GitHub: https://github.com/FlashLabs-AI-Corp/FlashLabs-Chroma
- Demo: https://flashlabs.ai/flashai-voice-agents

---

## Requirements

- **Python:** 3.11+ (uses ~/venv/chroma-voice/)
- **RAM:** ~16GB (6B parameter model on CPU)
- **GPU:** CUDA 12.6+ for fast inference. For AMD on Windows, use DirectML (torch-directml) via the PowerShell wrapper.
- **Storage:** ~12GB for model weights

---

## Installation

```bash
# Create Python 3.12 venv
python3.12 -m venv ~/venv/chroma-voice
source ~/venv/chroma-voice/bin/activate

# Install dependencies
pip install torch transformers accelerate soundfile scipy
```

### Windows + AMD (DirectML)

Install Windows Python 3.12 + `torch-directml` + `transformers` and set:

```bash
export OPENCLAW_DEVICE=directml
export OPENCLAW_WIN_PYTHON="C:\\Python312\\python.exe"
```

This will route Chroma requests through `chroma-chat-directml.ps1` on Windows so your RX 6800 is used.

---

## Usage

### Voice Conversation (speech-to-speech)

```bash
# Respond to audio input
/home/shkas/projects/raaz/skills/chroma-voice/scripts/chroma-chat.sh \
    --audio /path/to/input.ogg \
    --out /tmp/response.ogg
```

### Voice Cloning

```bash
# Clone a voice from reference audio
/home/shkas/projects/raaz/skills/chroma-voice/scripts/chroma-chat.sh \
    --audio /path/to/input.ogg \
    --voice-ref /path/to/reference.wav \
    --voice-text "Sample text spoken in reference" \
    --out /tmp/response.ogg
```

---

## Performance

| Mode | Hardware | Latency |
|------|----------|---------|
| GPU (CUDA) | RTX 3090 | ~150ms |
| CPU | 16-core | ~30-60s |

**Note:** On CPU (current setup), responses will be slow (~30-60s). This is a 6B parameter model.

---

## Architecture

- **Reasoner:** Qwen2.5-Omni-3B (speech understanding + reasoning)
- **Backbone:** Llama3 (16 layers, 2048 hidden)
- **Decoder:** Llama3 (4 layers, 1024 hidden)
- **Codec:** Mimi (24kHz audio)

---

## Use Cases

1. **Voice Assistant** - Talk to it, get voice responses
2. **Voice Cloning** - Generate speech in any voice
3. **Dubbing** - Clone celebrity/character voices
4. **Podcast Generation** - Multi-voice conversations

---

## Limitations

- English only
- Slow on CPU (~30-60s per response)
- Requires significant RAM (16GB+)
- AMD GPU acceleration requires Windows DirectML; WSL Linux has no ROCm support for RX 6800
