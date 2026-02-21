---
name: pocket-tts
description: Kyutai Pocket TTS - CPU-friendly text-to-speech with voice cloning and voice-note helpers.
---

# Pocket TTS Skill

Kyutai Pocket TTS - A 100M parameter text-to-speech model that runs on CPU with high quality output.

---

## ⚠️ IMPORTANT: Automatic Voice Replies

**Voice replies are handled AUTOMATICALLY by the system.** Do NOT manually invoke Pocket TTS scripts for chat voice replies unless Pocket TTS is explicitly configured in `audio.reply.command`.

When responding to voice messages:
1. **Just reply with plain text** - do NOT run any TTS scripts manually
2. The system automatically converts your text response to voice using the configured TTS provider
3. Check `~/.openclaw/openclaw.json` → `audio.reply.command` to see which TTS is active

**Only use Pocket TTS scripts directly when:**
- Pocket TTS is configured as the active TTS in `audio.reply.command`, OR
- You need to generate audio files for non-chat purposes (e.g., creating audio content)

---

## Installation

Pocket TTS is installed at `/home/shkas/pocket-tts/` with a virtual environment at `/home/shkas/pocket-tts/venv/`.

### Prerequisites
- Python 3.10+
- PyTorch 2.5+
- ffmpeg (for OGG/Opus conversion)

## Usage

## Warm Server Mode (Recommended)

Pocket TTS is fastest when run as a **warm server** (model stays loaded in RAM).
This skill includes a server manager + a voice-note generator that auto-starts the server on demand.

### Server control
```bash
# Status (healthy/running)
pocket-tts-server-status

# Start server (idempotent)
pocket-tts-server-start

# Stop server
pocket-tts-server-stop
```

### Generate WhatsApp-ready voice note (OGG/Opus)
```bash
# Text → Pocket TTS server → WAV → ffmpeg → OGG
voice-note-pocket-tts --text "Hello Asif" --out /tmp/reply.ogg

# Print tag for Clawdbot reply pipelines
voice-note-pocket-tts --text "Hello" --out /tmp/reply.ogg --emit-tag

# Voice preset (maps to Pocket TTS voice_url)
voice-note-pocket-tts --text "Hello" --voice alba --out /tmp/reply.ogg

# Optional voice cloning from a WAV sample
voice-note-pocket-tts --text "Hello" --voice-wav /path/to/sample.wav --out /tmp/reply.ogg
```

### Legacy one-shot wrapper
```bash
pocket-tts-reply "Your message here" /tmp/reply.ogg
```

## Options

| Option | Description | Default |
|--------|-------------|---------|
| `--text` | Text to generate | "Hello world..." |
| `--voice` | Path to audio for voice cloning | `alba` (built-in) |
| `--output-path` | Output WAV file path | `./tts_output.wav` |
| `--device` | Device to use | `cpu` |
| `--temperature` | Generation temperature | 0.7 |
| `--quiet` | Disable logging | false |

## Voice Cloning

Pocket TTS supports voice cloning from audio samples:

```bash
pocket-tts generate \
    --text "This is my cloned voice" \
    --voice /path/to/my-voice-sample.wav \
    --output-path /tmp/cloned-output.wav
```

## Integration with Voice Pipeline

This skill is part of the voice-to-voice reply system:

```
Voice Note → Whisper (STT) → LLM Response → Pocket TTS → OGG/Opus → Send
```

### TTS Options Comparison

| Model | Quality | Speed | Offline | Voice Clone |
|-------|---------|-------|---------|-------------|
| **Pocket TTS** | ⭐⭐⭐⭐⭐ | Medium | ✅ | ✅ |
| **Piper** | ⭐⭐⭐ | Fast | ✅ | ❌ |
| **sag (ElevenLabs)** | ⭐⭐⭐⭐⭐ | Fast | ❌ | ✅ |

## API Server (Optional)

Pocket TTS can run as a FastAPI server:

```bash
source /home/shkas/pocket-tts/venv/bin/activate
pocket-tts serve --host 0.0.0.0 --port 8000
```

Then use HTTP:
```bash
curl -X POST "http://localhost:8000/generate" \
    -H "Content-Type: application/json" \
    -d '{"text": "Hello world"}' \
    --output output.wav
```

## Troubleshooting

### Model Download
On first run, Pocket TTS downloads the model from HuggingFace (~400MB). This may take a few minutes.

### Memory Usage
The model uses ~1-2GB RAM. Ensure sufficient memory is available.

### Slow Generation
CPU generation takes 5-15 seconds depending on text length. For faster generation, use a GPU with `--device cuda`.
