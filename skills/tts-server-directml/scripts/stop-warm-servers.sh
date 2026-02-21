#!/usr/bin/env bash
set -euo pipefail

is_true() {
  case "${1,,}" in
    1|true|yes|y|on)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

if ! command -v powershell.exe >/dev/null 2>&1; then
  echo "[stop-warm-servers] powershell.exe not found; cannot stop Windows warm servers." >&2
  exit 1
fi

stop_by_pidfile() {
  local label="$1"
  local pid_relpath="$2"
  powershell.exe -NoProfile -Command "\
\$p = Join-Path \$env:USERPROFILE '$pid_relpath'; \
if (Test-Path \$p) { \
  \$procId = Get-Content \$p -ErrorAction SilentlyContinue; \
  if (\$procId) { \
    try { Stop-Process -Id \$procId -Force -ErrorAction Stop; Write-Host '[stop-warm-servers] Stopped $label (PID ' \$procId ')'; } \
    catch { Write-Host '[stop-warm-servers] Failed to stop $label (PID ' \$procId '): ' \$_.Exception.Message; } \
  } else { \
    Write-Host '[stop-warm-servers] $label pidfile empty'; \
  } \
  Remove-Item \$p -ErrorAction SilentlyContinue; \
} else { \
  Write-Host '[stop-warm-servers] $label not running (pidfile missing)'; \
}"
}

stop_proxy() {
  if command -v systemctl >/dev/null 2>&1; then
    systemctl --user stop openclaw-embeddings-proxy.service >/dev/null 2>&1 || true
    return
  fi
  if command -v pkill >/dev/null 2>&1; then
    pkill -f "[e]mbeddings-proxy.py" >/dev/null 2>&1 || true
    pkill -f "embeddings-directml/scripts/embeddings-proxy.py" >/dev/null 2>&1 || true
  fi
}

stop_pocket_tts() {
  local stop_sh="/home/shkas/projects/raaz/skills/pocket-tts/scripts/server-stop.sh"
  if [[ -x "$stop_sh" ]]; then
    "$stop_sh" >/dev/null 2>&1 || true
  fi
}

stop_chatterbox_tts() {
  local stop_sh="/home/shkas/projects/raaz/skills/chatterbox-tts/scripts/server-stop.sh"
  if [[ -x "$stop_sh" ]]; then
    "$stop_sh" >/dev/null 2>&1 || true
  fi
}

stop_by_pidfile "TTS" ".openclaw\\tts-server-directml\\server.pid"
stop_by_pidfile "Qwen3-TTS" ".openclaw\\qwen3-tts\\server.pid"
stop_by_pidfile "Whisper" ".openclaw\\whisper-server\\server.pid"

embeddings_managed_by_systemd="${EMBEDDINGS_MANAGED_BY_SYSTEMD:-0}"
if is_true "$embeddings_managed_by_systemd"; then
  echo "[stop-warm-servers] Embeddings managed by dedicated systemd services; skipping direct stop." >&2
else
  stop_by_pidfile "Embeddings" ".openclaw\\embeddings-directml\\server.pid"
fi

stop_by_pidfile "Pocket TTS" ".openclaw\\pocket-tts\\server.pid"
stop_by_pidfile "VibeVoice" ".openclaw\\vibevoice\\server.pid"

if is_true "$embeddings_managed_by_systemd"; then
  echo "[stop-warm-servers] Embeddings proxy managed by dedicated systemd service; skipping proxy stop." >&2
else
  stop_proxy
fi

stop_pocket_tts
stop_chatterbox_tts

if [[ -x "/home/shkas/projects/raaz/skills/vibevoice/scripts/start-server.sh" ]]; then
  /home/shkas/projects/raaz/skills/vibevoice/scripts/start-server.sh stop >/dev/null 2>&1 || true
fi
