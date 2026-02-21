---
name: wipro-light-discovery
description: Discover and control likely Wipro or Tuya smart lights on the local network (Linux or WSL) using host/port signatures and optional TinyTuya LAN control commands.
---

# Wipro Light Discovery

## Overview

Use this skill when the user asks to find or control smart lights on their LAN, especially Wipro bulbs. It provides one script for discovery and another for local on/off/brightness/color control.

## When To Use

- "Scan my network for smart lights"
- "Find Wipro lights on my Wi-Fi"
- "Which IP is my Wipro/Tuya bulb?"
- "Show only high-confidence Wipro candidates"
- "Turn my Wipro light on/off"
- "Set bulb brightness/color from terminal"

## Quick Start

Discovery scan:

```bash
python3 /home/shkas/projects/raaz/skills/wipro-light-discovery/scripts/discover_wipro_lights.py
```

High-confidence Wipro-focused output:

```bash
python3 /home/shkas/projects/raaz/skills/wipro-light-discovery/scripts/discover_wipro_lights.py --only-wipro --vendor-lookup
```

Scan a specific subnet:

```bash
python3 /home/shkas/projects/raaz/skills/wipro-light-discovery/scripts/discover_wipro_lights.py --subnet 192.168.0.0/24
```

JSON output for automation:

```bash
python3 /home/shkas/projects/raaz/skills/wipro-light-discovery/scripts/discover_wipro_lights.py --format json
```

Install control dependency:

```bash
python3 -m pip install --user --break-system-packages tinytuya
```

Add a light for control:

```bash
python3 /home/shkas/projects/raaz/skills/wipro-light-discovery/scripts/control_wipro_lights.py \
  --name bedroom-bulb add \
  --device-id <DEVICE_ID> \
  --ip <LAN_IP> \
  --local-key <LOCAL_KEY> \
  --version 3.3 \
  --default
```

Control examples:

```bash
# list configured lights
python3 /home/shkas/projects/raaz/skills/wipro-light-discovery/scripts/control_wipro_lights.py list

# on/off
python3 /home/shkas/projects/raaz/skills/wipro-light-discovery/scripts/control_wipro_lights.py --name bedroom-bulb on
python3 /home/shkas/projects/raaz/skills/wipro-light-discovery/scripts/control_wipro_lights.py --name bedroom-bulb off

# brightness and color
python3 /home/shkas/projects/raaz/skills/wipro-light-discovery/scripts/control_wipro_lights.py --name bedroom-bulb brightness --percent 40
python3 /home/shkas/projects/raaz/skills/wipro-light-discovery/scripts/control_wipro_lights.py --name bedroom-bulb color --hex FFA500
```

## Core Behavior

- Detects local subnets automatically (Linux + Windows interface fallback in WSL).
- Finds live hosts by ping, then probes smart-device-relevant ports.
- Uses Tuya/Wipro hints from open ports, MAC vendor, and HTTP banners.
- Assigns confidence score and marks `wipro_likely` candidates.
- Stores local control device profiles in JSON config.
- Supports local LAN control for configured devices: `status`, `on`, `off`, `toggle`, `brightness`, `temperature`, `color`.
- Outputs Markdown table or JSON.

## Script Locations

`/home/shkas/projects/raaz/skills/wipro-light-discovery/scripts/discover_wipro_lights.py`
`/home/shkas/projects/raaz/skills/wipro-light-discovery/scripts/control_wipro_lights.py`

## References

`/home/shkas/projects/raaz/skills/wipro-light-discovery/references/tuya-credentials-setup.md`

## Notes

- Discovery is best-effort based on signatures; final confirmation may still require router/app lookup.
- Control requires valid Tuya credentials (`device_id`, `local_key`).
- Use `--allow-large` carefully on large networks to avoid long scans.
