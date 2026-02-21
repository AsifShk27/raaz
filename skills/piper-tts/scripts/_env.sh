#!/usr/bin/env bash
set -euo pipefail

# Piper TTS server defaults for Clawdbot warm mode

PIPER_TTS_HOST="${PIPER_TTS_HOST:-127.0.0.1}"
PIPER_TTS_PORT="${PIPER_TTS_PORT:-8098}"
PIPER_TTS_BASE_URL="http://${PIPER_TTS_HOST}:${PIPER_TTS_PORT}"

# Keep state in Clawdbot dir so it survives across workspaces
PIPER_TTS_STATE_DIR="${PIPER_TTS_STATE_DIR:-$HOME/.openclaw/piper-tts}"
PIPER_TTS_PID_FILE="$PIPER_TTS_STATE_DIR/server.pid"
PIPER_TTS_LOG_FILE="$PIPER_TTS_STATE_DIR/server.log"

# Piper binary and model configuration (use existing env vars)
PIPER_BIN="${PIPER_BIN:-piper}"
PIPER_VOICE_MODEL="${PIPER_VOICE_MODEL:-}"
PIPER_VOICE_CONFIG="${PIPER_VOICE_CONFIG:-}"

# Per-language model overrides (auto-detected from Unicode script)
PIPER_VOICE_MODEL_HI="${PIPER_VOICE_MODEL_HI:-}"
PIPER_VOICE_CONFIG_HI="${PIPER_VOICE_CONFIG_HI:-}"
PIPER_VOICE_MODEL_TE="${PIPER_VOICE_MODEL_TE:-}"
PIPER_VOICE_CONFIG_TE="${PIPER_VOICE_CONFIG_TE:-}"
PIPER_VOICE_MODEL_ML="${PIPER_VOICE_MODEL_ML:-}"
PIPER_VOICE_CONFIG_ML="${PIPER_VOICE_CONFIG_ML:-}"
PIPER_VOICE_MODEL_KN="${PIPER_VOICE_MODEL_KN:-}"
PIPER_VOICE_CONFIG_KN="${PIPER_VOICE_CONFIG_KN:-}"

# Piper synthesis parameters
PIPER_SPEAKER="${PIPER_SPEAKER:-}"
PIPER_LENGTH_SCALE="${PIPER_LENGTH_SCALE:-1.0}"
PIPER_NOISE_SCALE="${PIPER_NOISE_SCALE:-0.667}"
PIPER_NOISE_W="${PIPER_NOISE_W:-0.8}"

# Server startup timeout (first start loads model)
PIPER_TTS_START_TIMEOUT_SECONDS="${PIPER_TTS_START_TIMEOUT_SECONDS:-60}"

# Python with fastapi/uvicorn installed (trading-agent-runtime venv)
PIPER_TTS_PYTHON="${PIPER_TTS_PYTHON:-/home/shkas/trading-agent-runtime/.venv/bin/python3}"

mkdir -p "$PIPER_TTS_STATE_DIR"
