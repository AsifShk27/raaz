---
name: voice-to-text-local
description: Transcribe audio files to text using local Whisper. Supports automatic transcription of WhatsApp voice messages.
metadata: {"openclaw":{"emoji":"🎙️","requires":{"bins":["whisper"]}}}
---

# voice-to-text-local

Transcribe audio using OpenAI Whisper running locally (no API key, no cloud upload).

## Automatic WhatsApp Voice Transcription

To automatically transcribe incoming voice messages, add this to `~/.openclaw/openclaw.json`:

```json
{
  "audio": {
    "transcription": {
      "command": ["/home/shkas/projects/raaz/skills/voice-to-text-local/scripts/transcribe.sh", "{{MediaPath}}", "--model", "base"],
      "timeoutSeconds": 60
    },
    "reply": {
      "command": ["/home/shkas/projects/raaz/skills/voice-messaging/scripts/voice-note-active-tts.sh", "--text-file", "{{ReplyTextFile}}", "--out", "{{ReplyAudioPath}}", "--emit-tag"],
      "timeoutSeconds": 60
    }
  }
}
```

This enables full voice-to-voice conversations:
1. User sends voice message → automatically transcribed to text
2. AI processes the text and responds
3. Response text → automatically synthesized to voice
4. Voice message sent back to user

## Script Usage

```bash
# Basic transcription (outputs to stdout)
{baseDir}/scripts/transcribe.sh /path/to/audio.ogg

# Specify language for better accuracy
{baseDir}/scripts/transcribe.sh /path/to/audio.ogg --language Hindi

# Use larger model for accuracy (slower)
{baseDir}/scripts/transcribe.sh /path/to/audio.ogg --model large

# Use DirectML on Windows (AMD/Intel/NVIDIA)
{baseDir}/scripts/transcribe.sh /path/to/audio.ogg --model base --device directml

# Write to file instead of stdout
{baseDir}/scripts/transcribe.sh /path/to/audio.ogg --out /tmp/transcript.txt
```

### Options

| Option | Default | Description |
|--------|---------|-------------|
| `--model` | `base` | Whisper model: tiny, base, small, medium, large, turbo |
| `--language` | auto | Language hint: English, Hindi, en, hi, etc. |
| `--device` | auto | `cpu`, `cuda`, `directml` (DirectML requires Windows + torch-directml) |
| `--out` | stdout | Write to file instead of stdout |
| `--engine` | `auto` | DirectML engine: `auto`, `onnx`, `whisper` |
| `--use-server` | off | Prefer warm Whisper HTTP server when available |
| `--no-server` | off | Force local execution (ignore warm server) |
| `--server-host` | auto | Warm server host (WSL auto-detects Windows host) |
| `--server-port` | `8111` | Warm server port |

## Manual Transcription

When user asks to transcribe audio manually:

1. User provides an audio file (or says "transcribe this")
2. Run the script:
   ```bash
   {baseDir}/scripts/transcribe.sh recording.ogg
   ```
3. Show the transcribed text to user

## Voice Reply Integration

For voice-to-voice responses, combine with the voice-messaging skill:

```bash
# Transcribe incoming voice
transcript=$({baseDir}/scripts/transcribe.sh incoming.ogg)

# Generate voice reply
/home/shkas/projects/raaz/skills/voice-messaging/scripts/voice-note-active-tts.sh \
  --text "Your response here" \
  --emit-tag
```

## Privacy

- Whisper runs locally (no cloud upload)
- Audio files processed in temp directory
- Automatically cleaned up after transcription

## DirectML (AMD GPU on Windows)

To use your AMD GPU via DirectML, install Windows Python with `onnx-asr` + `onnxruntime-directml` (preferred),
or `openai-whisper` + `torch-directml` (fallback). Then run:

```bash
{baseDir}/scripts/transcribe.sh /path/to/audio.ogg --model base --device directml
```

This path uses the PowerShell script `scripts/transcribe-directml.ps1` and can be called from WSL.
When `--device directml` is set, it prefers ONNX Runtime (DirectML) via `onnx-asr` and maps `--model base` to
`onnx-community/whisper-base`. `medium`/`large` map to `whisper-small` for ONNX compatibility. To keep full
Whisper models (no downmapping), set `--engine whisper` or `WHISPER_ENGINE=whisper` (slower, higher accuracy).

To use a different ONNX Whisper repo, pass it directly:

```bash
{baseDir}/scripts/transcribe.sh /path/to/audio.ogg --device directml --model onnx-community/whisper-base
```

You can also pass `--model onnx:<repo>` to force an ONNX repo.

You can also set `OPENCLAW_DEVICE=directml` to make DirectML the default for this skill.

If your Windows Python is not in PATH, set `OPENCLAW_WIN_PYTHON` to the full Windows path (e.g., `C:\\Python312\\python.exe`).

## Warm Server (Windows DirectML)

To avoid cold-start latency, run a long-lived Whisper server on Windows and point WSL to it.

Start the server (Windows PowerShell):

```powershell
.\scripts\start-server-bg.ps1 -BindHost 0.0.0.0 -Port 8111 -Model medium -Device directml -Engine auto
```

Check health from WSL:

```bash
curl "http://$(openclaw_windows_host):8111/health"
```

Use it from WSL:

```bash
WHISPER_USE_SERVER=1 WHISPER_SERVER_HOST="$(openclaw_windows_host)" \
  {baseDir}/scripts/transcribe.sh /path/to/audio.ogg --model medium
```

Optional auto-start from WSL (spawns the Windows server on demand):

```bash
WHISPER_WARM_SERVER=1 {baseDir}/scripts/transcribe.sh /path/to/audio.ogg --model medium
```

If your server runs on Windows and you need to force Windows path conversion, set `WHISPER_SERVER_WINDOWS=1`.

### Autostart with OpenClaw

If you want the Whisper warm server to start when you launch OpenClaw, use the wrapper:

```bash
/home/shkas/projects/raaz/skills/tts-server-directml/scripts/openclaw-with-tts.sh
```

This starts both TTS and Whisper warm servers (set `WHISPER_AUTOSTART=0` to skip Whisper).

To stop the warm servers:

```bash
/home/shkas/projects/raaz/skills/tts-server-directml/scripts/stop-warm-servers.sh
```

## Models

| Model | Speed | Accuracy | Size |
|-------|-------|----------|------|
| tiny | Fastest | Basic | 39M |
| base | Fast | Good | 74M |
| small | Medium | Better | 244M |
| medium | Slow | Great | 769M |
| large | Slowest | Best | 1550M |
| turbo | Slow on CPU | Great | 809M |

Change `--model` in the config to switch models. For always-on WhatsApp auto-transcription, `base` is the most reliable (fast + low RAM). `turbo` can exceed a 60s timeout on CPU; use a higher `timeoutSeconds` (e.g. 180) if you want it.
