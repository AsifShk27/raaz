---
name: tapo-snapshot
description: On-demand (privacy-first) snapshot or clip from Tapo cameras via camsnap. No cron, no background capture.
metadata: {"clawdbot":{"emoji":"📷","requires":{"bins":["camsnap"]}}}
---

# tapo-snapshot (privacy-first)

Take a **single snapshot or short video clip** from a Tapo camera using `camsnap` and send it back.

## Privacy rules
- **On-demand only** (never schedule, never poll).
- Store output in `/tmp` only.
- After sending, **delete** the local file.
- Never print credentials in logs/chat.

## Configuration (camsnap)
Camera credentials are stored in `~/.config/camsnap/config.yaml` (managed by camsnap):

```bash
camsnap add --name tapo-c210 --host 192.168.0.105 --user raazai --pass 'raaz@ai84'
```

## Usage patterns

### Snapshot
```bash
camsnap snap tapo-c210 --out /tmp/snap.jpg
```

### 5‑second video clip
```bash
camsnap clip tapo-c210 --dur 5s --out /tmp/clip.mp4
```

### Motion watch (on-demand check)
```bash
camsnap watch tapo-c210 --threshold 0.2 --json
```

## Command recipe
1. Build command from prompt intent:
   - "snapshot" → `camsnap snap tapo-c210 --out /tmp/out.jpg`
   - "clip" or "5 second video" → `camsnap clip tapo-c210 --dur 5s --out /tmp/out.mp4`
2. Execute and capture output path.
3. Send the file to the user (WhatsApp).
4. Delete local file: `rm -f /tmp/out.jpg /tmp/out.mp4`.

## Notes
- Requires `ffmpeg` on PATH (camsnap dependency).
- Default output: `/tmp/camsnap-*.jpg` if `--out` omitted.
- Credentials never printed in chat/logs.
