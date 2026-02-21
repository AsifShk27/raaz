# Pocket TTS autostart for Clawdbot

## What “autostart” means here

- The Pocket TTS model is heavy to load.
- We run `pocket-tts serve` as a local FastAPI server so the model stays warm.
- The `voice-note-pocket-tts` script will *auto-start the server on demand* if it isn’t already running.

That gives you “autostart UX” without needing systemd.

## Recommended Clawdbot config (voice replies)

Set `audio.reply.command` to the Pocket TTS voice-note script and increase timeout (first cold start can take >60s).

Example:

```json
{
  "audio": {
    "reply": {
      "command": [
        "/home/shkas/projects/raaz/skills/pocket-tts/scripts/voice-note-pocket-tts.sh",
        "--text-file",
        "{{ReplyTextFile}}",
        "--out",
        "{{ReplyAudioPath}}",
        "--emit-tag"
      ],
      "timeoutSeconds": 300
    }
  }
}
```

## Optional: warm the server at boot

If you want the **first reply** after reboot to be fast, run this once after startup:

```bash
pocket-tts-server-start
```

You can automate that via:
- a shell profile (`~/.bashrc`), or
- Clawdbot cron job that runs `pocket-tts-server-start` periodically, or
- a Windows/WSL startup task.
