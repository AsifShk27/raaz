---
name: embeddings-directml
description: Local OpenAI-compatible embeddings server on Windows using DirectML (AMD/Intel/NVIDIA) + WSL proxy and OpenClaw memory config.
metadata: {"openclaw":{"emoji":"🧠","requires":{"bins":["powershell.exe","python3"]}}}
---

# embeddings-directml

Local GPU embeddings for OpenClaw memory search using a Windows DirectML server (OpenAI-compatible `/v1/embeddings`) and a small WSL proxy so WSL can always call `http://127.0.0.1:8124/v1/`.

## What this skill sets up

- Windows embeddings server (DirectML + Transformers)
- WSL proxy (for stable localhost access)
- Systemd user services to auto-start with OpenClaw
- OpenClaw memorySearch config to use the local endpoint

## Key files

- Server (Windows): `scripts/embeddings-server.py`
- Server launcher (Windows): `scripts/start-server-detached.ps1`
- Proxy (WSL): `scripts/embeddings-proxy.py`

## Default model

`BAAI/bge-base-en-v1.5` (768-dim). Override with `EMBEDDINGS_MODEL`.

## Environment variables

- `EMBEDDINGS_MODEL` – HF model id (default: `BAAI/bge-base-en-v1.5`)
- `EMBEDDINGS_DEVICE` – `directml` (default), `cpu`
- `EMBEDDINGS_POOLING` – `cls` (default), `mean`
- `EMBEDDINGS_PORT` – Windows server port (default: `8124`)
- `EMBEDDINGS_PROXY_PORT` – WSL proxy port (default: `8124`)
- `EMBEDDINGS_WARM` – warm the model on start (default: `1`)
- `EMBEDDINGS_HEALTH_WAIT_SECONDS` – wait for server health on start (default: `20`)
- `EMBEDDINGS_PRELOAD` – preload model on server startup (default: `1`)

## Health checks

- WSL proxy: `http://127.0.0.1:8124/health`
- Windows server: `http://<windows-host>:8124/health`

## Systemd services

- `openclaw-embeddings-directml.service` (Windows server)
- `openclaw-embeddings-proxy.service` (WSL proxy)

## Autostart with OpenClaw

Use the OpenClaw wrapper to start embeddings automatically:

```bash
/home/shkas/projects/raaz/skills/tts-server-directml/scripts/openclaw-with-tts.sh
```

Disable embeddings autostart if needed:

```bash
EMBEDDINGS_AUTOSTART=0 /home/shkas/projects/raaz/skills/tts-server-directml/scripts/openclaw-with-tts.sh
```

## Notes

- This is for **OpenClaw memory embeddings** only (not general model inference).
- DirectML runs on Windows. WSL calls the proxy on localhost which forwards to Windows.
- If you want a different embedding model, update `EMBEDDINGS_MODEL` in the service and restart.
