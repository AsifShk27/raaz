---
name: samsung-tv
description: Control Samsung Smart TV - power, volume, apps, input switching via SmartThings API or local WebSocket.
metadata: {"openclaw":{"emoji":"📺","requires":{"python":["samsungtvws","wakeonlan","requests"]}}}
---

# Samsung TV Control

Control your Samsung Smart TV remotely. Supports power on/off, volume, mute, app launching, and input switching.

## TV Configuration

| Property | Value |
|----------|-------|
| **Model** | QA55QN85FAULXL (55" Neo QLED 4K) |
| **IP Address** | 192.168.0.102 |
| **MAC Address** | 94:e6:ba:79:2a:32 |
| **API** | SmartThings (recommended for 2024+ models) |

## Setup

### Option 1: SmartThings API (Recommended for 2024+ TVs)

1. Ensure TV is added to SmartThings app on your phone
2. Get API token from https://account.smartthings.com/tokens
   - Select scopes: Devices (all), Installed Applications
   - Copy the token immediately (shown only once)
3. Get Device ID: In SmartThings app, tap TV → Settings → Device ID
4. Configure:
   ```bash
   # Save credentials
   mkdir -p ~/.config/samsung-tv
   echo "YOUR_TOKEN" > ~/.config/samsung-tv/smartthings_token
   echo "YOUR_DEVICE_ID" > ~/.config/samsung-tv/device_id
   ```

### Option 2: Local WebSocket (Older TVs, pre-2024)

1. Enable IP Remote: TV Settings → General → Network → Expert → IP Remote
2. Run any command - accept the popup on TV
3. Token auto-saved to `~/.config/samsung-tv/token.txt`

## Scripts

| Script | Description |
|--------|-------------|
| `tv.sh` | Main control script (power, volume, keys, apps) |
| `wake.sh` | Wake TV via Wake-on-LAN |

## Usage

### Power

```bash
# Wake TV from standby (Wake-on-LAN)
/home/shkas/projects/raaz/skills/samsung-tv/scripts/wake.sh

# Power off
/home/shkas/projects/raaz/skills/samsung-tv/scripts/tv.sh power off

# Toggle power
/home/shkas/projects/raaz/skills/samsung-tv/scripts/tv.sh power
```

### Volume

```bash
# Volume up/down
/home/shkas/projects/raaz/skills/samsung-tv/scripts/tv.sh volume up
/home/shkas/projects/raaz/skills/samsung-tv/scripts/tv.sh volume down

# Set specific volume (0-100)
/home/shkas/projects/raaz/skills/samsung-tv/scripts/tv.sh volume 25

# Mute toggle
/home/shkas/projects/raaz/skills/samsung-tv/scripts/tv.sh mute
```

### Apps

```bash
# Launch Netflix
/home/shkas/projects/raaz/skills/samsung-tv/scripts/tv.sh app netflix

# Launch YouTube
/home/shkas/projects/raaz/skills/samsung-tv/scripts/tv.sh app youtube

# Launch Prime Video
/home/shkas/projects/raaz/skills/samsung-tv/scripts/tv.sh app prime

# Launch Disney+
/home/shkas/projects/raaz/skills/samsung-tv/scripts/tv.sh app disney

# List installed apps
/home/shkas/projects/raaz/skills/samsung-tv/scripts/tv.sh apps
```

### Input/Source

```bash
# Switch to HDMI 1
/home/shkas/projects/raaz/skills/samsung-tv/scripts/tv.sh input hdmi1

# Switch to HDMI 2
/home/shkas/projects/raaz/skills/samsung-tv/scripts/tv.sh input hdmi2

# Switch to TV tuner
/home/shkas/projects/raaz/skills/samsung-tv/scripts/tv.sh input tv
```

### Navigation Keys

```bash
# Send remote key
/home/shkas/projects/raaz/skills/samsung-tv/scripts/tv.sh key HOME
/home/shkas/projects/raaz/skills/samsung-tv/scripts/tv.sh key BACK
/home/shkas/projects/raaz/skills/samsung-tv/scripts/tv.sh key ENTER
/home/shkas/projects/raaz/skills/samsung-tv/scripts/tv.sh key UP
/home/shkas/projects/raaz/skills/samsung-tv/scripts/tv.sh key DOWN
/home/shkas/projects/raaz/skills/samsung-tv/scripts/tv.sh key LEFT
/home/shkas/projects/raaz/skills/samsung-tv/scripts/tv.sh key RIGHT
```

### Status

```bash
# Check TV status
/home/shkas/projects/raaz/skills/samsung-tv/scripts/tv.sh status
```

## Common App IDs

| App | ID |
|-----|-----|
| Netflix | `3201907018807` |
| YouTube | `111299001912` |
| Prime Video | `3201910019365` |
| Disney+ | `3201901017640` |
| Apple TV | `3201807016597` |
| Spotify | `3201606009684` |
| Plex | `3201512006963` |

## Troubleshooting

### TV won't wake up
- Ensure "Power On with Mobile" is enabled: Settings → General → Network → Expert
- Check MAC address is correct
- TV must be in standby (not fully powered off at wall)

### SmartThings API errors
- Verify token is valid and has correct scopes
- Check device ID is correct
- Ensure TV is online in SmartThings app

### Local WebSocket unauthorized
- 2024+ Samsung TVs may block local connections
- Use SmartThings API instead
- Or try: Settings → General → Network → Expert → IP Remote → Off, then On

## Notes

- Wake-on-LAN works even when TV is in standby
- SmartThings API requires internet connection
- Local WebSocket works without internet but may not work on newer TVs
- Volume changes may have slight delay via SmartThings API
