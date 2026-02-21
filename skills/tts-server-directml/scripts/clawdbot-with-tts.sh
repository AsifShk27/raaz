#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
COMMON_DEVICE="$SKILLS_ROOT/_common/device.sh"
if [[ -f "$COMMON_DEVICE" ]]; then
  # shellcheck source=/dev/null
  source "$COMMON_DEVICE"
fi

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

openclaw_config="${OPENCLAW_CONFIG:-$HOME/.openclaw/openclaw.json}"

read_audio_arg() {
  local section="$1"
  local flag="$2"
  local cfg="$openclaw_config"
  if [[ ! -f "$cfg" ]]; then
    return 1
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    return 1
  fi
  python3 - "$cfg" "$section" "$flag" <<'PY'
import json
import shlex
import sys

cfg, section, flag = sys.argv[1:4]
try:
    with open(cfg, "r", encoding="utf-8") as f:
        data = json.load(f)
except Exception:
    sys.exit(1)

audio = data.get("audio") or {}
node = audio.get(section) or {}
cmd = node.get("command")
if not cmd:
    sys.exit(1)

if isinstance(cmd, str):
    try:
        parts = shlex.split(cmd)
    except Exception:
        parts = cmd.split()
else:
    parts = [str(x) for x in cmd]

for idx, val in enumerate(parts):
    if val == flag and idx + 1 < len(parts):
        print(parts[idx + 1])
        sys.exit(0)
    if val.startswith(flag + "="):
        print(val.split("=", 1)[1])
        sys.exit(0)
sys.exit(1)
PY
}

reply_command_contains() {
  local needle="$1"
  local cfg="$openclaw_config"
  if [[ ! -f "$cfg" ]]; then
    return 1
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    return 1
  fi
  python3 - "$cfg" "$needle" <<'PY'
import json
import shlex
import sys

cfg, needle = sys.argv[1:3]
needle = needle.lower()
try:
    with open(cfg, "r", encoding="utf-8") as f:
        data = json.load(f)
except Exception:
    sys.exit(1)

audio = data.get("audio") or {}
node = audio.get("reply") or {}
cmd = node.get("command")
if not cmd:
    sys.exit(1)

if isinstance(cmd, str):
    try:
        parts = shlex.split(cmd)
    except Exception:
        parts = cmd.split()
else:
    parts = [str(x) for x in cmd]

for part in parts:
    if needle in str(part).lower():
        print("true")
        sys.exit(0)
sys.exit(1)
PY
}

json_get() {
  local key="$1"
  if ! command -v python3 >/dev/null 2>&1; then
    return 1
  fi
  python3 - "$key" <<'PY'
import json
import sys

key = sys.argv[1]
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(1)

value = data
for part in key.split("."):
    if isinstance(value, dict):
        value = value.get(part)
    else:
        value = None
        break

if value is None:
    sys.exit(1)

print(value)
PY
}

stop_warm_servers() {
  local stop_script="$SKILLS_ROOT/tts-server-directml/scripts/stop-warm-servers.sh"
  if [[ -x "$stop_script" ]]; then
    "$stop_script" || true
  else
    echo "[openclaw-with-tts] Missing warm server stop script: $stop_script" >&2
  fi
}

stop_windows_pidfile() {
  local label="$1"
  local pid_relpath="$2"
  if ! command -v powershell.exe >/dev/null 2>&1; then
    echo "[openclaw-with-tts] powershell.exe not found; cannot stop $label." >&2
    return 1
  fi
  powershell.exe -NoProfile -Command "\
\$p = Join-Path \$env:USERPROFILE '$pid_relpath'; \
if (Test-Path \$p) { \
  \$procId = Get-Content \$p -ErrorAction SilentlyContinue; \
  if (\$procId) { \
    try { Stop-Process -Id \$procId -Force -ErrorAction Stop; } catch {} \
  } \
  Remove-Item \$p -ErrorAction SilentlyContinue; \
}"
}

is_gateway_stop=false
skip_server_start=false
if [[ "${1:-}" == "gateway" && "${2:-}" == "stop" ]]; then
  is_gateway_stop=true
  stop_warm_servers
fi
# Skip server startup for agent/sessions commands (servers should already be running from gateway)
if [[ "${1:-}" == "agent" || "${1:-}" == "sessions" || "${1:-}" == "memory" ]]; then
  skip_server_start=true
fi

server_host="${TTS_SERVER_HOST:-localhost}"
server_port="${TTS_SERVER_PORT:-8099}"
default_model="${TTS_MODEL:-piper}"
device="${OPENCLAW_DEVICE:-directml}"
bind_host="$server_host"
reply_uses_qwen3=false
reply_uses_pocket=false
reply_uses_directml_tts=false
reply_uses_vibevoice=false
directml_autostart="${DIRECTML_TTS_AUTOSTART:-}"

if reply_command_contains "qwen3" >/dev/null 2>&1; then
  reply_uses_qwen3=true
fi
if reply_command_contains "pocket-tts" >/dev/null 2>&1; then
  reply_uses_pocket=true
fi
if reply_command_contains "tts-server-directml" >/dev/null 2>&1 || reply_command_contains "tts-client.sh" >/dev/null 2>&1; then
  reply_uses_directml_tts=true
fi
if reply_command_contains "vibevoice" >/dev/null 2>&1; then
  reply_uses_vibevoice=true
fi

if [[ -z "${TTS_SERVER_PORT:-}" ]]; then
  port_from_cfg="$(read_audio_arg reply --port || true)"
  if [[ -n "$port_from_cfg" ]]; then
    server_port="$port_from_cfg"
  fi
fi

if [[ -z "${TTS_MODEL:-}" ]]; then
  model_from_cfg="$(read_audio_arg reply --model || true)"
  if [[ -n "$model_from_cfg" ]]; then
    default_model="$model_from_cfg"
  fi
fi

if [[ -z "${TTS_SERVER_HOST:-}" ]]; then
  host_from_cfg="$(read_audio_arg reply --server || true)"
  if [[ -n "$host_from_cfg" ]]; then
    server_host="$host_from_cfg"
  fi
fi

if [[ "${device,,}" != "directml" && "${device,,}" != "dml" ]]; then
  device="cpu"
fi

if [[ "$server_host" == "localhost" || "$server_host" == "127.0.0.1" ]]; then
  if [[ "$(type -t openclaw_windows_host || true)" == "function" ]]; then
    server_host="$(openclaw_windows_host)"
    bind_host="0.0.0.0"
  fi
fi

start_server() {
  if ! command -v powershell.exe >/dev/null 2>&1; then
    echo "[openclaw-with-tts] powershell.exe not found; skipping DirectML TTS autostart." >&2
    return 1
  fi

  local start_ps="$SKILLS_ROOT/tts-server-directml/scripts/start-server-bg.ps1"
  if [[ ! -f "$start_ps" ]]; then
    echo "[openclaw-with-tts] Missing start script: $start_ps" >&2
    return 1
  fi

  local start_ps_win
  start_ps_win="$(wslpath -w "$start_ps")"

  local ps_args=(
    -NoProfile -ExecutionPolicy Bypass -File "$start_ps_win"
    -BindHost "$bind_host"
    -Port "$server_port"
    -DefaultModel "$default_model"
    -Device "$device"
  )

  if [[ -n "${OPENCLAW_WIN_PYTHON:-}" ]]; then
    ps_args+=( -PythonPath "${OPENCLAW_WIN_PYTHON}" )
  fi

  powershell.exe "${ps_args[@]}"
}

if [[ -z "$directml_autostart" ]]; then
  if $reply_uses_directml_tts; then
    directml_autostart=1
  else
    directml_autostart=0
  fi
fi

if is_true "$directml_autostart"; then
  if [[ "$is_gateway_stop" != "true" && "$skip_server_start" != "true" ]]; then
    if ! curl -s --connect-timeout 2 "http://${server_host}:${server_port}/health" >/dev/null 2>&1; then
      echo "[openclaw-with-tts] Starting DirectML TTS server..." >&2
      if ! start_server; then
        echo "[openclaw-with-tts] TTS autostart failed; continuing to launch OpenClaw." >&2
      fi
    fi
  fi
fi

qwen3_autostart="${QWEN3_AUTOSTART:-}"
qwen3_host="${QWEN3_TTS_HOST:-127.0.0.1}"
qwen3_port="${QWEN3_TTS_PORT:-8099}"
qwen3_device="${QWEN3_TTS_DEVICE:-${OPENCLAW_DEVICE:-directml}}"
qwen3_model="${QWEN3_TTS_MODEL:-}"
qwen3_model_dir="${QWEN3_TTS_MODEL_DIR:-$HOME/.openclaw/qwen3-tts/models/Qwen3-TTS-12Hz-1.7B-VoiceDesign}"
qwen3_bind_host="$qwen3_host"

if [[ "$qwen3_host" == "localhost" || "$qwen3_host" == "127.0.0.1" ]]; then
  if [[ "$(type -t openclaw_windows_host || true)" == "function" ]]; then
    qwen3_host="$(openclaw_windows_host)"
    qwen3_bind_host="0.0.0.0"
  fi
fi

start_qwen3_server() {
  if ! command -v powershell.exe >/dev/null 2>&1; then
    echo "[openclaw-with-tts] powershell.exe not found; skipping Qwen3-TTS autostart." >&2
    return 1
  fi

  local start_ps="$SKILLS_ROOT/qwen3-tts/scripts/server-start.ps1"
  if [[ ! -f "$start_ps" ]]; then
    echo "[openclaw-with-tts] Missing Qwen3-TTS start script: $start_ps" >&2
    return 1
  fi

  local start_ps_win
  start_ps_win="$(wslpath -w "$start_ps")"

  local ps_args=(
    -NoProfile -ExecutionPolicy Bypass -File "$start_ps_win"
    -BindHost "$qwen3_bind_host"
    -Port "$qwen3_port"
    -Device "$qwen3_device"
  )

  if [[ -n "$qwen3_model" ]]; then
    ps_args+=( -Model "$(wslpath -w "$qwen3_model")" )
  elif [[ -n "$qwen3_model_dir" && -d "$qwen3_model_dir" ]]; then
    ps_args+=( -Model "$(wslpath -w "$qwen3_model_dir")" )
  fi

  if [[ -n "${OPENCLAW_WIN_PYTHON:-}" ]]; then
    ps_args+=( -PythonPath "${OPENCLAW_WIN_PYTHON}" )
  fi

  powershell.exe "${ps_args[@]}"
}

pocket_autostart="${POCKET_TTS_AUTOSTART:-}"
pocket_host="${POCKET_TTS_HOST:-127.0.0.1}"
pocket_port="${POCKET_TTS_PORT:-8101}"
pocket_device="${POCKET_TTS_DEVICE:-auto}"
pocket_bind_host="$pocket_host"
pocket_use_windows=false

if command -v powershell.exe >/dev/null 2>&1; then
  if [[ "${pocket_device,,}" != "cpu" ]]; then
    pocket_use_windows=true
  fi
fi

if $pocket_use_windows; then
  if [[ "$pocket_host" == "localhost" || "$pocket_host" == "127.0.0.1" ]]; then
    if [[ "$(type -t openclaw_windows_host || true)" == "function" ]]; then
      pocket_host="$(openclaw_windows_host)"
      pocket_bind_host="0.0.0.0"
    fi
  fi
fi

if [[ -z "$pocket_autostart" ]]; then
  if $reply_uses_pocket; then
    pocket_autostart=1
  else
    pocket_autostart=0
  fi
fi

if [[ -z "$qwen3_autostart" ]]; then
  if $reply_uses_qwen3; then
    qwen3_autostart=1
  else
    qwen3_autostart=0
  fi
fi

start_pocket_tts_server() {
  local start_ps="$SKILLS_ROOT/pocket-tts/scripts/server-start.ps1"
  local start_sh="$SKILLS_ROOT/pocket-tts/scripts/server-start.sh"
  if $pocket_use_windows; then
    if [[ -f "$start_ps" ]]; then
      if [[ -x "$SKILLS_ROOT/pocket-tts/scripts/server-stop.sh" ]]; then
        "$SKILLS_ROOT/pocket-tts/scripts/server-stop.sh" >/dev/null 2>&1 || true
      fi
      local start_ps_win
      start_ps_win="$(wslpath -w "$start_ps")"
      local ps_args=(
        -NoProfile -ExecutionPolicy Bypass -File "$start_ps_win"
        -BindHost "$pocket_bind_host"
        -Port "$pocket_port"
        -Device "$pocket_device"
      )
      if [[ -n "${OPENCLAW_WIN_PYTHON:-}" ]]; then
        ps_args+=( -PythonPath "${OPENCLAW_WIN_PYTHON}" )
      fi
      if powershell.exe "${ps_args[@]}"; then
        return 0
      fi
      echo "[openclaw-with-tts] Pocket TTS Windows start failed; falling back to WSL." >&2
    else
      echo "[openclaw-with-tts] Missing Pocket TTS Windows start script: $start_ps" >&2
    fi
  fi
  if [[ ! -x "$start_sh" ]]; then
    echo "[openclaw-with-tts] Missing Pocket TTS start script: $start_sh" >&2
    return 1
  fi
  POCKET_TTS_HOST="$pocket_host" \
    POCKET_TTS_PORT="$pocket_port" \
    POCKET_TTS_DEVICE="$pocket_device" \
    "$start_sh"
}

if is_true "$pocket_autostart"; then
  if [[ "$is_gateway_stop" != "true" && "$skip_server_start" != "true" ]]; then
    if ! curl -s --connect-timeout 2 "http://${pocket_host}:${pocket_port}/health" >/dev/null 2>&1; then
      echo "[openclaw-with-tts] Starting Pocket TTS warm server..." >&2
      if ! start_pocket_tts_server; then
        echo "[openclaw-with-tts] Pocket TTS autostart failed; continuing to launch OpenClaw." >&2
      fi
    fi
  fi
fi

export POCKET_TTS_HOST="$pocket_host"
export POCKET_TTS_PORT="$pocket_port"
export POCKET_TTS_DEVICE="$pocket_device"

if is_true "$qwen3_autostart"; then
  if [[ "$is_gateway_stop" != "true" && "$skip_server_start" != "true" ]]; then
    if ! curl -s --connect-timeout 2 "http://${qwen3_host}:${qwen3_port}/health" >/dev/null 2>&1; then
      echo "[openclaw-with-tts] Starting Qwen3-TTS warm server..." >&2
      if ! start_qwen3_server; then
        echo "[openclaw-with-tts] Qwen3-TTS autostart failed; continuing to launch OpenClaw." >&2
      fi
    fi
  fi
fi

vibevoice_autostart="${VIBEVOICE_AUTOSTART:-}"
vibevoice_host="${VIBEVOICE_SERVER_HOST:-127.0.0.1}"
vibevoice_port="${VIBEVOICE_SERVER_PORT:-7860}"
vibevoice_device="${VIBEVOICE_DEVICE:-${OPENCLAW_DEVICE:-auto}}"
vibevoice_checkpoint="${VIBEVOICE_CHECKPOINT:-/home/shkas/projects/raaz/VibeVoice/checkpoints/VibeVoice-Realtime-0.5B}"
vibevoice_voice="${VIBEVOICE_VOICE:-Samuel}"
vibevoice_bind_host="$vibevoice_host"
vibevoice_use_windows=false

if [[ -z "$vibevoice_autostart" ]]; then
  if $reply_uses_vibevoice; then
    vibevoice_autostart=1
  else
    vibevoice_autostart=0
  fi
fi

if command -v powershell.exe >/dev/null 2>&1; then
  if [[ "${vibevoice_device,,}" == "directml" || "${vibevoice_device,,}" == "dml" ]]; then
    vibevoice_use_windows=true
  fi
fi

if $vibevoice_use_windows; then
  if [[ "$vibevoice_host" == "localhost" || "$vibevoice_host" == "127.0.0.1" ]]; then
    if [[ "$(type -t openclaw_windows_host || true)" == "function" ]]; then
      vibevoice_host="$(openclaw_windows_host)"
      vibevoice_bind_host="0.0.0.0"
    fi
  fi
fi

start_vibevoice_server() {
  local start_ps="$SKILLS_ROOT/vibevoice/scripts/start-server-directml.ps1"
  local start_sh="$SKILLS_ROOT/vibevoice/scripts/start-server.sh"
  if $vibevoice_use_windows; then
    if [[ -f "$start_ps" ]]; then
      local start_ps_win
      start_ps_win="$(wslpath -w "$start_ps")"
      local repo_root="$SKILLS_ROOT/../VibeVoice"
      local repo_root_win="$(wslpath -w "$repo_root")"
      local checkpoint_arg="$vibevoice_checkpoint"
      if [[ -n "$vibevoice_checkpoint" && -d "$vibevoice_checkpoint" ]]; then
        checkpoint_arg="$(wslpath -w "$vibevoice_checkpoint")"
      fi
      local ps_args=(
        -NoProfile -ExecutionPolicy Bypass -File "$start_ps_win"
        -BindHost "$vibevoice_bind_host"
        -Port "$vibevoice_port"
        -Device "$vibevoice_device"
        -RepoRoot "$repo_root_win"
        -Checkpoint "$checkpoint_arg"
        -Voice "$vibevoice_voice"
      )
      if [[ -n "${OPENCLAW_WIN_PYTHON:-}" ]]; then
        ps_args+=( -PythonPath "${OPENCLAW_WIN_PYTHON}" )
      fi
      powershell.exe "${ps_args[@]}"
      return $?
    else
      echo "[openclaw-with-tts] Missing VibeVoice DirectML start script: $start_ps" >&2
      return 1
    fi
  fi

  if [[ ! -x "$start_sh" ]]; then
    echo "[openclaw-with-tts] Missing VibeVoice start script: $start_sh" >&2
    return 1
  fi

  VIBEVOICE_CHECKPOINT="$vibevoice_checkpoint" \
    VIBEVOICE_DEVICE="$vibevoice_device" \
    VIBEVOICE_VOICE="$vibevoice_voice" \
    VIBEVOICE_SERVER_PORT="$vibevoice_port" \
    "$start_sh" start
}

if is_true "$vibevoice_autostart"; then
  if [[ "$is_gateway_stop" != "true" && "$skip_server_start" != "true" ]]; then
    if ! curl -s --connect-timeout 2 "http://${vibevoice_host}:${vibevoice_port}/health" >/dev/null 2>&1; then
      echo "[openclaw-with-tts] Starting VibeVoice warm server..." >&2
      if ! start_vibevoice_server; then
        echo "[openclaw-with-tts] VibeVoice autostart failed; continuing to launch OpenClaw." >&2
      fi
    fi
  fi
fi

export VIBEVOICE_SERVER_URL="http://${vibevoice_host}:${vibevoice_port}"

whisper_autostart="${WHISPER_AUTOSTART:-1}"
whisper_host="${WHISPER_SERVER_HOST:-${WHISPER_HOST:-}}"
whisper_port="${WHISPER_SERVER_PORT:-${WHISPER_PORT:-}}"
whisper_model="${WHISPER_MODEL:-}"
whisper_device="${WHISPER_DEVICE:-${OPENCLAW_DEVICE:-directml}}"
whisper_engine="${WHISPER_ENGINE:-auto}"

if [[ -z "${WHISPER_SERVER_PORT:-}" && -z "${WHISPER_PORT:-}" ]]; then
  port_from_cfg="$(read_audio_arg transcription --server-port || true)"
  if [[ -n "$port_from_cfg" ]]; then
    whisper_port="$port_from_cfg"
  fi
fi

if [[ -z "${WHISPER_SERVER_HOST:-}" && -z "${WHISPER_HOST:-}" ]]; then
  host_from_cfg="$(read_audio_arg transcription --server-host || true)"
  if [[ -n "$host_from_cfg" ]]; then
    whisper_host="$host_from_cfg"
  fi
fi

if [[ -z "${WHISPER_MODEL:-}" ]]; then
  model_from_cfg="$(read_audio_arg transcription --model || true)"
  if [[ -n "$model_from_cfg" ]]; then
    whisper_model="$model_from_cfg"
  fi
fi

if [[ -z "${WHISPER_ENGINE:-}" ]]; then
  engine_from_cfg="$(read_audio_arg transcription --engine || true)"
  if [[ -n "$engine_from_cfg" ]]; then
    whisper_engine="$engine_from_cfg"
  fi
fi

whisper_host="${whisper_host:-localhost}"
whisper_port="${whisper_port:-8111}"
whisper_model="${whisper_model:-medium}"
whisper_bind_host="$whisper_host"

if [[ "${whisper_device,,}" != "directml" && "${whisper_device,,}" != "dml" ]]; then
  whisper_device="cpu"
fi
if [[ "${whisper_engine,,}" == "auto" && ( "${whisper_device,,}" == "directml" || "${whisper_device,,}" == "dml" ) ]]; then
  whisper_engine="onnx"
fi

if [[ "$whisper_host" == "localhost" || "$whisper_host" == "127.0.0.1" ]]; then
  if [[ "$(type -t openclaw_windows_host || true)" == "function" ]]; then
    whisper_host="$(openclaw_windows_host)"
    whisper_bind_host="0.0.0.0"
  fi
fi

start_whisper_server() {
  if ! command -v powershell.exe >/dev/null 2>&1; then
    echo "[openclaw-with-tts] powershell.exe not found; skipping Whisper autostart." >&2
    return 1
  fi

  local start_ps="$SKILLS_ROOT/voice-to-text-local/scripts/start-server-bg.ps1"
  if [[ ! -f "$start_ps" ]]; then
    echo "[openclaw-with-tts] Missing Whisper start script: $start_ps" >&2
    return 1
  fi

  local start_ps_win
  start_ps_win="$(wslpath -w "$start_ps")"

  local ps_args=(
    -NoProfile -ExecutionPolicy Bypass -File "$start_ps_win"
    -BindHost "$whisper_bind_host"
    -Port "$whisper_port"
    -Model "$whisper_model"
    -Device "$whisper_device"
    -Engine "$whisper_engine"
  )

  if [[ -n "${OPENCLAW_WIN_PYTHON:-}" ]]; then
    ps_args+=( -PythonPath "${OPENCLAW_WIN_PYTHON}" )
  fi

  powershell.exe "${ps_args[@]}"
}

if [[ "$is_gateway_stop" != "true" && "$skip_server_start" != "true" ]]; then
  if is_true "$whisper_autostart"; then
    whisper_health="$(curl -s --connect-timeout 2 "http://${whisper_host}:${whisper_port}/health" || true)"
    whisper_restart=false
    if [[ -n "$whisper_health" ]]; then
      server_engine="$(printf '%s' "$whisper_health" | json_get engine || true)"
      server_device="$(printf '%s' "$whisper_health" | json_get device || true)"
      if [[ "${whisper_device,,}" == "directml" && "${server_device,,}" != "directml" ]]; then
        whisper_restart=true
      fi
      if [[ -n "${whisper_engine:-}" && "${whisper_engine,,}" != "auto" && -n "$server_engine" \
        && "${server_engine,,}" != "${whisper_engine,,}" ]]; then
        whisper_restart=true
      fi
    fi
    if [[ -z "$whisper_health" || "$whisper_restart" == "true" ]]; then
      echo "[openclaw-with-tts] Starting Whisper warm server..." >&2
      if [[ "$whisper_restart" == "true" ]]; then
        stop_windows_pidfile "Whisper" ".openclaw\\whisper-server\\server.pid" || true
      fi
      if ! start_whisper_server; then
        echo "[openclaw-with-tts] Whisper autostart failed; continuing to launch OpenClaw." >&2
      fi
    fi
  fi
fi

embeddings_autostart="${EMBEDDINGS_AUTOSTART:-1}"
embeddings_warm="${EMBEDDINGS_WARM:-1}"
embeddings_host="${EMBEDDINGS_SERVER_HOST:-${EMBEDDINGS_HOST:-}}"
embeddings_port="${EMBEDDINGS_PORT:-8124}"
embeddings_model="${EMBEDDINGS_MODEL:-BAAI/bge-base-en-v1.5}"
embeddings_device="${EMBEDDINGS_DEVICE:-directml}"
embeddings_pooling="${EMBEDDINGS_POOLING:-cls}"
embeddings_proxy_host="${EMBEDDINGS_PROXY_HOST:-127.0.0.1}"
embeddings_proxy_port="${EMBEDDINGS_PROXY_PORT:-8124}"
embeddings_bind_host="$embeddings_host"

if [[ "${embeddings_device,,}" != "directml" && "${embeddings_device,,}" != "dml" ]]; then
  embeddings_device="cpu"
fi

if [[ -z "$embeddings_host" || "$embeddings_host" == "localhost" || "$embeddings_host" == "127.0.0.1" ]]; then
  if [[ "$(type -t openclaw_windows_host || true)" == "function" ]]; then
    embeddings_host="$(openclaw_windows_host)"
    embeddings_bind_host="0.0.0.0"
  else
    embeddings_host="127.0.0.1"
  fi
fi

start_embeddings_server() {
  if ! command -v powershell.exe >/dev/null 2>&1; then
    echo "[openclaw-with-tts] powershell.exe not found; skipping embeddings autostart." >&2
    return 1
  fi

  local start_ps="$SKILLS_ROOT/embeddings-directml/scripts/start-server-detached.ps1"
  if [[ ! -f "$start_ps" ]]; then
    echo "[openclaw-with-tts] Missing embeddings start script: $start_ps" >&2
    return 1
  fi

  local start_ps_win
  start_ps_win="$(wslpath -w "$start_ps")"

  local ps_args=(
    -NoProfile -ExecutionPolicy Bypass -File "$start_ps_win"
    -BindHost "$embeddings_bind_host"
    -Port "$embeddings_port"
    -Model "$embeddings_model"
    -Device "$embeddings_device"
    -Pooling "$embeddings_pooling"
  )

  if [[ -n "${OPENCLAW_WIN_PYTHON:-}" ]]; then
    ps_args+=( -PythonPath "${OPENCLAW_WIN_PYTHON}" )
  fi

  powershell.exe "${ps_args[@]}"
}

start_embeddings_proxy() {
  if command -v systemctl >/dev/null 2>&1; then
    systemctl --user start openclaw-embeddings-proxy.service >/dev/null 2>&1 && return 0
  fi
  local proxy_script="$SKILLS_ROOT/embeddings-directml/scripts/embeddings-proxy.py"
  if [[ ! -f "$proxy_script" ]]; then
    echo "[openclaw-with-tts] Missing embeddings proxy script: $proxy_script" >&2
    return 1
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    echo "[openclaw-with-tts] python3 not found; skipping embeddings proxy." >&2
    return 1
  fi
  EMBEDDINGS_WINDOWS_HOST="$embeddings_host" \
    EMBEDDINGS_WINDOWS_PORT="$embeddings_port" \
    EMBEDDINGS_PROXY_HOST="$embeddings_proxy_host" \
    EMBEDDINGS_PROXY_PORT="$embeddings_proxy_port" \
    nohup python3 "$proxy_script" >/tmp/embeddings-proxy.log 2>&1 &
}

wait_for_embeddings_health() {
  local host="$1"
  local port="$2"
  local timeout="${EMBEDDINGS_HEALTH_WAIT_SECONDS:-20}"
  local deadline=$((SECONDS + timeout))
  local resp=""
  while ((SECONDS < deadline)); do
    resp="$(curl -s --connect-timeout 2 "http://${host}:${port}/health" || true)"
    if [[ -n "$resp" ]]; then
      printf '%s' "$resp"
      return 0
    fi
    sleep 1
  done
  return 1
}

if [[ "$is_gateway_stop" != "true" && "$skip_server_start" != "true" ]]; then
  if is_true "$embeddings_autostart"; then
    embeddings_health="$(curl -s --connect-timeout 2 "http://${embeddings_host}:${embeddings_port}/health" || true)"
    embeddings_device_state=""
    if [[ -n "$embeddings_health" ]]; then
      embeddings_device_state="$(printf '%s' "$embeddings_health" | json_get device || true)"
    fi
    if [[ -z "$embeddings_health" ]]; then
      echo "[openclaw-with-tts] Starting embeddings server..." >&2
      if ! start_embeddings_server; then
        echo "[openclaw-with-tts] Embeddings autostart failed; continuing to launch OpenClaw." >&2
      fi
      embeddings_health="$(wait_for_embeddings_health "$embeddings_host" "$embeddings_port" || true)"
      if [[ -n "$embeddings_health" ]]; then
        embeddings_device_state="$(printf '%s' "$embeddings_health" | json_get device || true)"
      fi
    fi
    if is_true "$embeddings_warm"; then
      curl -s --connect-timeout 2 -X POST \
        "http://${embeddings_host}:${embeddings_port}/v1/embeddings" \
        -H "Content-Type: application/json" \
        -d '{"input":"warmup"}' >/dev/null 2>&1 || true
      embeddings_health="$(wait_for_embeddings_health "$embeddings_host" "$embeddings_port" || true)"
      if [[ -n "$embeddings_health" ]]; then
        embeddings_device_state="$(printf '%s' "$embeddings_health" | json_get device || true)"
      fi
    fi
    if [[ "${embeddings_device,,}" == "directml" && "${embeddings_device_state,,}" != "directml" ]]; then
      echo "[openclaw-with-tts] Embeddings running on ${embeddings_device_state:-unknown}; restarting for DirectML..." >&2
      stop_windows_pidfile "Embeddings" ".openclaw\\embeddings-directml\\server.pid" || true
      if start_embeddings_server; then
        if is_true "$embeddings_warm"; then
          curl -s --connect-timeout 2 -X POST \
            "http://${embeddings_host}:${embeddings_port}/v1/embeddings" \
            -H "Content-Type: application/json" \
            -d '{"input":"warmup"}' >/dev/null 2>&1 || true
        fi
      else
        echo "[openclaw-with-tts] Embeddings autostart failed; continuing to launch OpenClaw." >&2
      fi
    fi
    start_embeddings_proxy || true
  fi
fi

openclaw_bin="$(command -v openclaw || true)"
if [[ -z "$openclaw_bin" ]]; then
  echo "[openclaw-with-tts] 'openclaw' not found in PATH." >&2
  exit 1
fi

self_path="$(readlink -f "$0" || echo "$0")"
openclaw_path="$(readlink -f "$openclaw_bin" || echo "$openclaw_bin")"
if [[ "$self_path" == "$openclaw_path" ]]; then
  while IFS= read -r cand; do
    cand_path="$(readlink -f "$cand" || echo "$cand")"
    if [[ "$cand_path" != "$self_path" ]]; then
      openclaw_bin="$cand"
      break
    fi
  done < <(command -v -a openclaw 2>/dev/null || true)
fi

exec "$openclaw_bin" "$@"
