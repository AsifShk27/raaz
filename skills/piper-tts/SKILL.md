---
name: piper-tts
description: Offline, on-prem TTS voice-note replies using Piper (Rhasspy) + ffmpeg. Produces WhatsApp/Telegram-friendly OGG/Opus.
---

# Piper TTS (On-Prem Voice Replies)

This skill adds a **local/offline** TTS pipeline for Clawdbot voice-note replies using **Piper** (Rhasspy) and `ffmpeg`.

---

## ⚠️ IMPORTANT: Automatic Voice Replies

**Voice replies are handled AUTOMATICALLY by the system.** Do NOT manually invoke Piper scripts for chat voice replies unless Piper is explicitly configured in `audio.reply.command`.

When responding to voice messages:
1. **Just reply with plain text** - do NOT run any TTS scripts manually
2. The system automatically converts your text response to voice using the configured TTS provider
3. Check `~/.openclaw/openclaw.json` → `audio.reply.command` to see which TTS is active

**Only use Piper scripts directly when:**
- Piper is configured as the active TTS in `audio.reply.command`, OR
- You need to generate audio files for non-chat purposes (e.g., creating audio content)

---

## What it does

- Accepts text (or a text file)
- Runs Piper to synthesize audio (WAV)
- Converts WAV → OGG/Opus for "voice note" compatibility
- Optionally emits Clawdbot media tags

## Prerequisites

- `piper` on PATH (or set `PIPER_BIN`)
- A Piper voice model `.onnx` file (set `PIPER_VOICE_MODEL`)
- `ffmpeg` on PATH
- Python 3.10+ with `fastapi`, `uvicorn` (for warm mode)

## AMD GPU (DirectML on Windows)

If you want Piper to run on your RX 6800 GPU, the scripts will route to the
Windows DirectML server (`tts-server-directml`) when `OPENCLAW_DEVICE=directml`.

Required:
- Windows Python 3.12 with `torch-directml`, `onnxruntime-directml`, `piper-tts`
- `OPENCLAW_DEVICE=directml`
- `OPENCLAW_WIN_PYTHON="C:\\Python312\\python.exe"` (optional, but recommended)

If you already have a local Piper model (`PIPER_VOICE_MODEL`), the script will
sync it to Windows and use it via the DirectML server. You can also set
`PIPER_VOICE_ID` to a Piper voice name (e.g., `en_US-amy-medium`) to skip syncing.

## Scripts

| Script | Description |
|--------|-------------|
| `voice-note-piper-warm.sh` | **PRIMARY** - Uses HTTP server, auto-starts, fast (<1s) |
| `server-start.sh` | Start warm server manually |
| `server-stop.sh` | Stop warm server |
| `server-status.sh` | Check server health |
| `voice-note-piper.sh` | Legacy cold mode (slow, not recommended) |

---

## Warm Mode (Default)

Warm mode keeps the Piper model loaded in memory, eliminating the ~2-4s model load time per request.

### How it works

1. First voice reply triggers `server-start.sh` automatically
2. Server loads model once and stays running (~100-500MB RAM)
3. Subsequent requests are fast (<1s synthesis)
4. Server runs on `http://127.0.0.1:8098` by default

### Server management

```bash
# Check status
/home/shkas/projects/raaz/skills/piper-tts/scripts/server-status.sh

# Start manually (e.g., at boot)
/home/shkas/projects/raaz/skills/piper-tts/scripts/server-start.sh

# Stop server
/home/shkas/projects/raaz/skills/piper-tts/scripts/server-stop.sh
```

### Optional: Pre-warm at startup

Add to `~/.bashrc` or a startup script:

```bash
export PIPER_VOICE_MODEL="/path/to/your/model.onnx"
/home/shkas/projects/raaz/skills/piper-tts/scripts/server-start.sh &
```

---

## Environment Variables

### Required

| Variable | Description |
|----------|-------------|
| `PIPER_VOICE_MODEL` | Path to `.onnx` voice model (required) |

### Optional

| Variable | Default | Description |
|----------|---------|-------------|
| `PIPER_BIN` | `piper` | Path to piper binary |
| `PIPER_VOICE_CONFIG` | - | Path to model `.json` config |
| `PIPER_VOICE_ID` | - | Voice name for DirectML server (e.g., `en_US-amy-medium`) |
| `PIPER_SPEAKER` | - | Speaker ID for multi-speaker models |
| `PIPER_LENGTH_SCALE` | `1.0` | Speaking rate (lower = faster) |
| `PIPER_NOISE_SCALE` | `0.667` | Voice variation |
| `PIPER_NOISE_W` | `0.8` | Phoneme width noise |
| `PIPER_MAX_CHARS` | `6000` | Max text length |

### Per-language model overrides

Auto-selected by Unicode script detection:

| Variable | Script |
|----------|--------|
| `PIPER_VOICE_MODEL_HI` | Devanagari (Hindi) |
| `PIPER_VOICE_MODEL_TE` | Telugu |
| `PIPER_VOICE_MODEL_ML` | Malayalam |
| `PIPER_VOICE_MODEL_KN` | Kannada |

Each can have a matching `_CONFIG` variant (e.g., `PIPER_VOICE_CONFIG_HI`).

### Server configuration (warm mode)

| Variable | Default | Description |
|----------|---------|-------------|
| `PIPER_TTS_HOST` | `127.0.0.1` | Server bind address |
| `PIPER_TTS_PORT` | `8098` | Server port |
| `PIPER_TTS_START_TIMEOUT_SECONDS` | `60` | Startup timeout |

### DirectML server (Windows)

When `OPENCLAW_DEVICE=directml`, the scripts use the Windows DirectML server on
`TTS_SERVER_HOST` / `TTS_SERVER_PORT` (default: `localhost:8099`) and will
auto-start it if needed.

---

## Quick Test

```bash
export PIPER_VOICE_MODEL="/home/shkas/.local/share/piper/voices/en_US-lessac-high.onnx"

# First call starts server (slower)
/home/shkas/projects/raaz/skills/piper-tts/scripts/voice-note-piper-warm.sh \
  --text "Hello, first request starts the server" \
  --out /tmp/warm-test-1.ogg

# Second call is fast (<1s)
/home/shkas/projects/raaz/skills/piper-tts/scripts/voice-note-piper-warm.sh \
  --text "This one is much faster!" \
  --out /tmp/warm-test-2.ogg

mpv /tmp/warm-test-2.ogg
```

---

## Troubleshooting

### Server won't start
```bash
# Check logs
cat ~/.openclaw/piper-tts/server.log

# Verify model path
echo $PIPER_VOICE_MODEL
ls -la $PIPER_VOICE_MODEL
```

### Server not responding
```bash
# Check if process is running
cat ~/.openclaw/piper-tts/server.pid
ps aux | grep piper_server

# Restart
/home/shkas/projects/raaz/skills/piper-tts/scripts/server-stop.sh
/home/shkas/projects/raaz/skills/piper-tts/scripts/server-start.sh
```

### Python dependencies missing
```bash
pip install fastapi uvicorn python-multipart
```

---

## Performance Comparison

| Mode | First Request | Subsequent | Memory |
|------|--------------|------------|--------|
| Warm (default) | ~2-4s (startup) | <1s | ~100-500MB |
| Cold (legacy) | ~2-4s | ~2-4s | 0 when idle |

---

## Legacy: Cold Mode

> **Note:** Cold mode is deprecated. Use warm mode (`voice-note-piper-warm.sh`) instead.

Cold mode spawns a new piper process per request. Only use if warm mode is unavailable.

```bash
/home/shkas/projects/raaz/skills/piper-tts/scripts/voice-note-piper.sh \
  --text "Hello, this is cold mode Piper TTS" \
  --out /tmp/cold-test.ogg
```
