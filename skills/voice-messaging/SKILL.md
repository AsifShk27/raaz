---
name: voice-messaging
description: "End-to-end voice messaging workflows: voice note transcription, text replies, optional TTS voice responses, and real-time voice-to-voice talk mode. Use when building or operating voice input/output flows, configuring audio transcription commands, generating voice note replies, or enabling speaker playback."
---

# Voice Messaging

## Overview

Enable voice-in to text-out by default, and add optional voice replies or real-time voice-to-voice when a speaker-capable node is available.

## Workflow Decision Tree

- Need live, low-latency back-and-forth with a speaker? Use Talk Mode (voice-to-voice).
- Need text replies only? Use Transcribe -> Text Reply.
- Need a voice note reply in chat? Use Text Reply -> TTS -> Voice Note.

## Workflow 1: Voice Note -> Text Reply (default)

1. Accept a voice note or audio file.
2. Transcribe with a local or cloud STT CLI that prints the transcript to stdout.
3. Send the transcript into the normal text reply flow.

Use local Whisper manually:

```bash
whisper /path/audio.m4a --model turbo --output_format txt --output_dir /tmp
cat /tmp/audio.txt
```

Configure Clawdbot audio transcription (CLI must print text to stdout):

```json5
{
  "audio": {
    "transcription": {
      "command": ["/path/to/whisper-stdout.sh", "{{MediaPath}}", "/tmp"],
      "timeoutSeconds": 45
    }
  }
}
```

Minimal wrapper for Whisper (store on disk, add to PATH):

```bash
#!/usr/bin/env bash
set -euo pipefail
in="${1:?audio file required}"
outdir="${2:-/tmp}"
whisper "$in" --model turbo --output_format txt --output_dir "$outdir" >/dev/null 2>&1
base="$(basename "$in")"
txt="${base%.*}.txt"
cat "$outdir/$txt"
```

## Workflow 2: Voice-to-Voice Reply (voice note)

1. Transcribe the inbound voice note (Workflow 1).
2. Generate the normal text response.
3. Run the TTS helper to produce an OGG/Opus voice note.
4. Attach the audio and keep the text reply.

Use the active-TTS helper (reads `~/.openclaw/openclaw.json` `audio.reply.command`, with router fallback):

```bash
/home/shkas/projects/raaz/skills/voice-messaging/scripts/voice-note-active-tts.sh \
  --text "Your response text here" \
  --out /tmp/reply.ogg
```

The helper injects `{{ReplyTextFile}}` and `{{ReplyAudioPath}}` into the active reply command.
Use provider-specific scripts directly only when intentionally testing a specific backend.

Emit the message lines directly (audio only, no text):

```bash
/home/shkas/projects/raaz/skills/voice-messaging/scripts/voice-note-active-tts.sh \
  --text "Your response text here" \
  --emit-tag
```

Send as a voice note (Telegram/WhatsApp style):

```
[[audio_as_voice]]
MEDIA:/tmp/reply.ogg
```

For WhatsApp, keep the text reply and add the media line:

```
Here is the response text.
MEDIA:/tmp/reply.ogg
```

## Workflow 3: Real-Time Voice-to-Voice (Talk Mode)

1. Ensure an iOS/Android/mac node is connected with mic + speaker permissions.
2. Enable Talk Mode on the device.
3. Speak; the node streams STT locally, sends text to the main session, and plays TTS audio.
4. Keep text replies in chat history while speaking responses aloud.

Use this for hands-free, low-latency conversation. Fall back to text-only or voice-note replies when no speaker-capable node is connected.

Configure Talk defaults in `~/.openclaw/openclaw.json`:

```json5
{
  talk: {
    voiceId: "elevenlabs_voice_id",
    voiceAliases: {
      Clawd: "EXAVITQu4vr4xnSDxMaL",
      Roger: "CwhRBWXzGAHq8TQ4Fs17"
    },
    modelId: "eleven_v3",
    outputFormat: "mp3_44100_128",
    apiKey: "elevenlabs_api_key",
    interruptOnSpeech: true
  }
}
```

Notes:
- `talk.apiKey` falls back to `ELEVENLABS_API_KEY` (or the gateway shell profile) when unset.
- `talk.voiceAliases` lets you use friendly names for `--voice` (voice-note replies) and Talk directives.

## Output Selection Rules

- Prefer Talk Mode when a speaker-capable node is connected and the user wants voice output.
- Otherwise, send text replies and optionally include a voice note.
- Always keep the text reply; treat audio as an augmentation.

## Automatic WhatsApp Voice Replies

**IMPORTANT: Voice replies are handled AUTOMATICALLY by the system when `audio.reply` is configured.**

When replying to a WhatsApp voice message:
- Just return your normal TEXT response - do NOT manually run `voice-note-active-tts.sh`
- The system automatically detects the inbound was audio
- The system automatically converts your text response to voice
- The system automatically sends the voice message back

**DO NOT:**
- Run `voice-note-active-tts.sh` manually via bash
- Return status messages about creating audio files
- Include MEDIA: tags manually

**DO:**
- Just respond conversationally with text
- Let the automatic system handle voice conversion

## Constraints

- Keep inbound audio <=5 MB for transcription pipelines.
- Keep outbound voice notes <=16 MB.
- TTS dependencies are provider-specific; verify the active `audio.reply.command` backend is healthy.
