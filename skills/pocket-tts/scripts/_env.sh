#!/usr/bin/env bash
set -euo pipefail

# Pocket TTS server defaults for Clawdbot

POCKET_TTS_VENV="${POCKET_TTS_VENV:-/home/shkas/pocket-tts/venv}"
POCKET_TTS_HOST="${POCKET_TTS_HOST:-127.0.0.1}"
POCKET_TTS_PORT="${POCKET_TTS_PORT:-8101}"
POCKET_TTS_DEVICE="${POCKET_TTS_DEVICE:-auto}"

script_path="$(readlink -f "${BASH_SOURCE[0]}")"
script_dir="$(cd -- "$(dirname -- "$script_path")" && pwd)"
common_device="${script_dir}/../_common/device.sh"
if [[ -f "$common_device" ]]; then
  # shellcheck source=/dev/null
  source "$common_device"
fi

if [[ "${POCKET_TTS_DEVICE,,}" == "directml" || "${POCKET_TTS_DEVICE,,}" == "dml" ]]; then
  if [[ "$POCKET_TTS_HOST" == "localhost" || "$POCKET_TTS_HOST" == "127.0.0.1" ]]; then
    if [[ "$(type -t openclaw_windows_host || true)" == "function" ]]; then
      POCKET_TTS_HOST="$(openclaw_windows_host)"
    fi
  fi
fi

POCKET_TTS_BASE_URL="http://${POCKET_TTS_HOST}:${POCKET_TTS_PORT}"

# Keep state in Clawdbot dir so it survives across workspaces
POCKET_TTS_STATE_DIR="${POCKET_TTS_STATE_DIR:-$HOME/.openclaw/pocket-tts}"
POCKET_TTS_PID_FILE="$POCKET_TTS_STATE_DIR/server.pid"
POCKET_TTS_LOG_FILE="$POCKET_TTS_STATE_DIR/server.log"

POCKET_TTS_DEFAULT_VOICE="${POCKET_TTS_DEFAULT_VOICE:-alba}"

mkdir -p "$POCKET_TTS_STATE_DIR"
