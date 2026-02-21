---
name: vibevoice
description: Microsoft's open-source frontier voice AI for expressive TTS. Integrates with Clawdbot voice-to-voice pipeline.
---

# VibeVoice TTS Skill

Microsoft's open-source frontier voice AI for generating expressive, natural-sounding speech from text.

## Features

- **Expressive TTS**: Natural-sounding speech with emotions and prosody
- **Multiple voices**: English, Chinese, German, French, Italian, Japanese, Korean, Dutch, Polish, Portuguese, Spanish
- **Real-time streaming**: ~300ms first chunk latency
- **Voice cloning**: Use voice presets for consistent speaker identity

## Prerequisites

1. **VibeVoice installed** at `/home/shkas/projects/raaz/VibeVoice`
2. **Model checkpoint** at `/home/shkas/projects/raaz/VibeVoice/checkpoints/VibeVoice-Realtime-0.5B`

## Available Voices

English voices:
- `en-Carter_man` - Male voice
- `en-Davis_man` - Male voice  
- `en-Mike_man` - Male voice
- `en-Frank_man` - Male voice
- `en-Emma_woman` - Female voice
- `en-Grace_woman` - Female voice
- `in-Samuel_man` - Indian English male voice

Other languages: `de-`, `fr-`, `it-`, `jp-`, `kr-`, `nl-`, `pl-`, `pt-`, `es-`, `zh-`

## Scripts

### voice-note-vibevoice.sh

Main TTS script for voice note generation. Drop-in replacement for piper-tts.

```bash
/home/shkas/projects/raaz/skills/vibevoice/scripts/voice-note-vibevoice.sh \
  --text "Hello, this is a test" \
  --out /tmp/output.ogg \
  --voice Samuel
```

Options:
- `--text TEXT` - Text to synthesize
- `--text-file FILE` - Read text from file
- `--out FILE` - Output file (WAV or OGG)
- `--voice NAME` - Voice preset name (default: Samuel)
- `--emit-tag` - Emit Clawdbot MEDIA tag

## Environment Variables

- `VIBEVOICE_CHECKPOINT` - Path to model checkpoint (default: auto-detected)
- `VIBEVOICE_DEVICE` - Device: cuda, mps, directml, cpu (default: auto)
- `VIBEVOICE_VOICE` - Default voice preset (default: Samuel)
- `VIBEVOICE_CFG_SCALE` - CFG scale for generation (default: 1.5)
- `OPENCLAW_DEVICE` - Global device hint (auto/directml/cuda/cpu)
- `OPENCLAW_WIN_PYTHON` - Windows Python for DirectML (e.g. C:\Python312\python.exe)

## Clawdbot Integration

### Option 1: Configure as audio.reply

Add to `~/.openclaw/openclaw.json`:

```json5
{
  "audio": {
    "reply": {
      "command": [
        "/home/shkas/projects/raaz/skills/vibevoice/scripts/voice-note-vibevoice.sh",
        "--text-file", "{{ReplyTextFile}}",
        "--out", "{{ReplyAudioPath}}",
        "--voice", "Samuel",
        "--emit-tag"
      ],
      "timeoutSeconds": 120,
      "voiceOnly": false
    }
  }
}
```

### Option 2: Switch between TTS engines

Create a wrapper script that selects TTS engine based on config:

```bash
# In ~/.openclaw/openclaw.json
{
  "audio": {
    "reply": {
      "command": [
        "/home/shkas/projects/raaz/skills/voice-messaging/scripts/tts-router.sh",
        "--text-file", "{{ReplyTextFile}}",
        "--out", "{{ReplyAudioPath}}"
      ]
    }
  }
}
```

## Downloading the Main Model

Available models on HuggingFace:

| Model | Size | Max Length | Link |
|-------|------|------------|------|
| VibeVoice-Realtime-0.5B | ~2GB | Streaming | [HuggingFace](https://huggingface.co/microsoft/VibeVoice-Realtime-0.5B) |
| VibeVoice-1.5B | ~6GB | 90 min | [HuggingFace](https://huggingface.co/microsoft/VibeVoice-1.5B) |
| VibeVoice-Large | ~12GB | 45 min | [HuggingFace](https://huggingface.co/microsoft/VibeVoice-Large) |

### To download VibeVoice-1.5B (recommended for quality):

```bash
python3.12 -c "
from huggingface_hub import snapshot_download
snapshot_download(
    repo_id='microsoft/VibeVoice-1.5B',
    local_dir='/home/shkas/projects/raaz/VibeVoice/checkpoints/VibeVoice-1.5B'
)
"
```

**Store location**: `/home/shkas/projects/raaz/VibeVoice/checkpoints/VibeVoice-1.5B`

Then update `VIBEVOICE_CHECKPOINT` to point to this new model.

## Performance Notes

- **GPU recommended**: CPU inference is slow (~10x realtime)
- **First run**: Model loading takes 30-60 seconds
- **Memory**: ~4GB RAM/VRAM for the 0.5B model

## AMD GPU (DirectML on Windows)

If you are on Windows with an AMD GPU (RX 6800), set:

```bash
export OPENCLAW_DEVICE=directml
export OPENCLAW_WIN_PYTHON="C:\\Python312\\python.exe"
```

This routes `voice-note-vibevoice.sh` through `voice-note-vibevoice-directml.ps1` so VibeVoice runs on DirectML.

## Responsible AI

⚠️ **Research Use Only**: Not for production without testing.

Please:
- Disclose AI-generated content
- Don't use for impersonation or deception
- Verify transcript accuracy
