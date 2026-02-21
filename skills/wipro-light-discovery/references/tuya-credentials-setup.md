# Tuya / Wipro Local Control Credential Setup

Local LAN control needs these values for each device:

- `device_id`
- `local_key`
- `ip`
- protocol version (`3.3` or `3.4` in most cases)

## How to get credentials (recommended path)

1. Keep the light linked to the Smart Life / Wipro Next app.
2. Create a Tuya IoT developer account and cloud project.
3. Link your Smart Life app account to that Tuya project.
4. Use TinyTuya wizard to pull local keys:

```bash
python3 -m pip install --user --break-system-packages tinytuya
python3 -m tinytuya wizard
```

5. Copy `id`, `key`, `ip`, and `version` for each bulb.

## Add device to this skill

```bash
python3 /home/shkas/projects/raaz/skills/wipro-light-discovery/scripts/control_wipro_lights.py \
  --name bedroom-bulb add \
  --device-id <DEVICE_ID> \
  --ip <LAN_IP> \
  --local-key <LOCAL_KEY> \
  --version 3.3 \
  --default
```

## Security note

`local_key` is sensitive. Treat the config file as a secret.
