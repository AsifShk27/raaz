---
name: whisper-cpp
description: Fast, lightweight speech-to-text using the Whisper.cpp C++ implementation.
---

# Whisper.cpp Skill

Fast, lightweight speech-to-text using OpenAI Whisper via C++ implementation.

## Installation

```bash
brew install whisper-cpp
```

### Model Files
Models are stored in `~/.cache/whisper/`:
- `ggml-base.bin` (147 MB) - fast, good accuracy
- `ggml-small.bin` (483 MB) - better accuracy
- `ggml-medium.bin` (1.5 GB) - high accuracy
- `ggml-large-v3.bin` (3.0 GB) - **best accuracy** (now installed!)

## Usage

```bash
# Transcribe an audio file
whisper-cpp audio.mp3

# Specify model
whisper-cpp audio.mp3 --model large-v3

# Options
--model <name>     Model to use
--language <lang>  Language (auto-detect if not set)
--threads <n>      CPU threads (default: 4)
```

## Model Comparison

| Model | Size | Speed | Accuracy |
|-------|------|-------|----------|
| base | 147 MB | ⚡⚡⚡⚡ | ⭐⭐⭐ |
| small | 483 MB | ⚡⚡⚡ | ⭐⭐⭐⭐ |
| medium | 1.5 GB | ⚡⚡ | ⭐⭐⭐⭐⭐ |
| large-v3 | 3.0 GB | ⚡ | ⭐⭐⭐⭐⭐ |

## Why whisper.cpp?

| | Python Whisper | Whisper.cpp |
|---|---|---|
| **Speed** | Medium | **~2-3x faster** |
| **Memory** | ~2-5 GB | **~1-2 GB** |
| **Dependencies** | PyTorch | None (standalone) |
| **Model Loading** | Slow | **Fast** |

Even without warm mode, whisper.cpp loads models faster and transcribes quicker!

## For Clawdbot Integration

Update `openclaw.json`:
```json
{
  "audio": {
    "transcription": {
      "command": [
        "/home/shkas/projects/raaz/skills/whisper-cpp/scripts/transcribe.sh",
        "{{MediaPath}}",
        "--model",
        "large-v3"
      ],
      "timeoutSeconds": 180
    }
  }
}
```

## Scripts

- `scripts/transcribe.sh` - Clawdbot-compatible transcription
- `scripts/server-control.sh` - Server control (if server mode is added)

## Notes

- No warm server mode (whisper.cpp doesn't have built-in server)
- But still **2-3x faster** than Python Whisper
- Model loads quickly, suitable for on-demand transcription

## AMD GPU (RX 6800) on Windows

whisper.cpp does not support DirectML, so on Windows + AMD the GPU path is:

- Set `OPENCLAW_DEVICE=directml`
- The scripts will route to `voice-to-text-local` (Python Whisper + torch-directml)

If you want native whisper.cpp GPU, build a Windows Vulkan binary (whisper.cpp
supports Vulkan) and wire it in separately. This repo defaults to DirectML for
AMD GPUs.
