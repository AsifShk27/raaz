---
name: chatterbox-tts
description: ResembleAI Chatterbox text-to-speech with a warm local server for Raaz voice-note replies. Use when configuring or operating Chatterbox voice replies, server health/start/stop, or troubleshooting Chatterbox runtime issues.
---

# Chatterbox TTS

Use this skill to run Chatterbox TTS as a warm server and generate WhatsApp-compatible voice notes.

## Runtime layout

- Skill path: `/home/shkas/projects/raaz/skills/chatterbox-tts`
- Runtime venv: `/home/shkas/projects/raaz/.runtime/chatterbox-tts/.venv`
- Default server: `http://127.0.0.1:8126`

## Commands

```bash
# Warm server controls
/home/shkas/projects/raaz/skills/chatterbox-tts/scripts/server-start.sh
/home/shkas/projects/raaz/skills/chatterbox-tts/scripts/server-status.sh
/home/shkas/projects/raaz/skills/chatterbox-tts/scripts/server-stop.sh

# Generate voice note
/home/shkas/projects/raaz/skills/chatterbox-tts/scripts/voice-note-chatterbox-warm.sh \
  --text "Hello from Chatterbox" \
  --out /tmp/chatterbox.ogg \
  --emit-tag
```

## Environment knobs

- `CHATTERBOX_TTS_HOST` (default `127.0.0.1`)
- `CHATTERBOX_TTS_PORT` (default `8126`)
- `CHATTERBOX_TTS_DEVICE` (`cpu` default)
- `CHATTERBOX_TTS_MODEL` (`turbo` default; values: `turbo`, `classic`)
- `CHATTERBOX_TTS_MAX_CHARS` (default `1200`)
- `CHATTERBOX_TTS_STARTUP_TIMEOUT_SECONDS` (default `300`)
- `CHATTERBOX_TTS_MODEL_ROOT` (default `$CHATTERBOX_TTS_RUNTIME/models`, persistent local snapshot path)
- `CHATTERBOX_TTS_LOCAL_ONLY` (default empty/auto: download once, then local-only on subsequent starts; set `1` to force local-only, `0` to always allow remote checks)
- `CHATTERBOX_TTS_RUNTIME` (default `/home/shkas/projects/raaz/.runtime/chatterbox-tts`)
- `CHATTERBOX_TTS_OUTPUT_BITRATE` (default `48k`, Opus target bitrate for voice-note encoding)
- `CHATTERBOX_TTS_OUTPUT_APPLICATION` (default `audio`, Opus tuning profile; `voip` is supported)
- `CHATTERBOX_TTS_OUTPUT_FILTER` (default `loudnorm=I=-18:TP=-2:LRA=11` for consistent playback loudness)

## DirectML status

DirectML mode is currently disabled by default because Chatterbox generation fails on current AMD DirectML runtime in this environment. If `CHATTERBOX_TTS_DEVICE=directml` is set, the server logs a warning and safely falls back to CPU.
