---
name: voice-to-text
description: Transcribe audio files to text and optionally send the result to the main session for processing. First step toward full voice assistant.
metadata: {"clawdbot":{"emoji":"🎙️","requires":{"bins":["whisper"]}}}
---

# voice-to-text

Transcribe audio using OpenAI Whisper (local, no API key).

## Usage
1. User provides an audio file (or says "transcribe this")
2. Run: `whisper audio_file.mp3 --model large --language English`
3. Output: transcribed text (`.txt` file alongside)
4. If requested, send the text to the main session for processing

## Example workflow
- User: "transcribe this audio" + attaches `recording.mp3`
- Assistant:
  ```bash
  whisper recording.mp3 --model small --language English --output_dir /tmp
  ```
  - Shows the transcribed text
  - Optionally: `sessions_send` to main session for Raaz to respond

## Privacy
- Whisper runs locally (no cloud upload)
- Audio files stored temporarily in `/tmp`
- Delete after transcription unless user wants to keep

## Next steps (future)
- Add ElevenLabs TTS for voice output
- Add wake word detection
- Continuous listen → transcribe → respond loop
