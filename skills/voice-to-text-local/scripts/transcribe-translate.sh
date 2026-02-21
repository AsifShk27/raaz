#!/usr/bin/env bash
set -euo pipefail

# Transcribe AND translate to English using Whisper's --task translate
# This is a wrapper that calls whisper with translation enabled.
#
# Usage:
#   transcribe-translate.sh <audio-file> [--model medium]
#
# For openclaw config:
#   "audio": {
#     "transcription": {
#       "command": ["{baseDir}/scripts/transcribe-translate.sh", "{{MediaPath}}", "--model", "medium"],
#       "timeoutSeconds": 120
#     }
#   }

usage() {
  cat >&2 <<'EOF'
Usage:
  transcribe-translate.sh <audio-file> [--model medium] [--device <cpu|cuda|directml>] [--engine <auto|onnx|whisper>]
                         [--use-server|--no-server] [--server-host <host>] [--server-port <port>]

Transcribes audio and translates to English (any language -> English).

Options:
  --model        Whisper model: tiny, base, small, medium, large, turbo (default: medium)
  --device       Device: cpu, cuda, directml (default: auto)
  --engine       Engine for DirectML: auto, onnx, whisper (default: auto)
  --use-server   Prefer warm Whisper HTTP server when available
  --no-server    Force local execution (ignore warm server)
  --server-host  Warm server host (default: auto-detect)
  --server-port  Warm server port (default: 8111)

Examples:
  transcribe-translate.sh recording.ogg                 # Translate to English
  transcribe-translate.sh recording.ogg --model large   # Use larger model
  transcribe-translate.sh recording.ogg --use-server    # Use warm server when available
EOF
  exit 2
}

if [[ "${1:-}" == "" || "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
COMMON_DEVICE="$SKILLS_ROOT/_common/device.sh"
if [[ -f "$COMMON_DEVICE" ]]; then
  # shellcheck source=/dev/null
  source "$COMMON_DEVICE"
fi

in="${1:-}"
shift || true

model="medium"
engine="${WHISPER_ENGINE:-auto}"
use_server="${WHISPER_USE_SERVER:-auto}"
server_host="${WHISPER_SERVER_HOST:-${WHISPER_HOST:-}}"
server_port="${WHISPER_SERVER_PORT:-${WHISPER_PORT:-8111}}"
server_windows="${WHISPER_SERVER_WINDOWS:-}"
device="${WHISPER_DEVICE:-${OPENCLAW_DEVICE:-}}"
if [[ -z "$device" && "$(type -t openclaw_device_default || true)" == "function" ]]; then
  device="$(openclaw_device_default)"
fi
if [[ "${device,,}" == "auto" ]]; then
  device=""
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --model)
      model="${2:-$model}"
      shift 2
      ;;
    --device)
      device="${2:-}"
      shift 2
      ;;
    --engine)
      engine="${2:-$engine}"
      shift 2
      ;;
    --use-server)
      use_server="true"
      shift
      ;;
    --no-server)
      use_server="false"
      shift
      ;;
    --server-host)
      server_host="${2:-$server_host}"
      shift 2
      ;;
    --server-port)
      server_port="${2:-$server_port}"
      shift 2
      ;;
    *)
      echo "Unknown arg: $1" >&2
      usage
      ;;
  esac
done

if [[ ! -f "$in" ]]; then
  echo "File not found: $in" >&2
  exit 1
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

resolve_server_host() {
  if [[ -n "$server_host" ]]; then
    echo "$server_host"
    return
  fi
  if [[ "$(type -t openclaw_windows_host || true)" == "function" ]]; then
    echo "$(openclaw_windows_host)"
    return
  fi
  echo "127.0.0.1"
}

server_host="$(resolve_server_host)"
server_port="${server_port:-8111}"
server_url="http://${server_host}:${server_port}"

server_on_windows=false
if is_true "$server_windows"; then
  server_on_windows=true
elif [[ "$(type -t openclaw_is_wsl || true)" == "function" ]]; then
  if openclaw_is_wsl; then
    if [[ "$(type -t openclaw_windows_host || true)" == "function" ]]; then
      win_host="$(openclaw_windows_host)"
      if [[ "$server_host" == "$win_host" ]]; then
        server_on_windows=true
      fi
    fi
  fi
fi

should_try_server=false
if is_true "$use_server"; then
  should_try_server=true
elif [[ "${use_server,,}" == "false" || "${use_server,,}" == "0" || "${use_server,,}" == "no" ]]; then
  should_try_server=false
else
  if [[ -n "${WHISPER_SERVER_HOST:-}" || -n "${WHISPER_SERVER_PORT:-}" ]]; then
    should_try_server=true
  elif [[ "${device,,}" == "directml" || "${device,,}" == "dml" ]]; then
    should_try_server=true
  fi
fi

start_warm_server() {
  if ! is_true "${WHISPER_WARM_SERVER:-${WHISPER_SERVER_AUTOSTART:-}}"; then
    return 1
  fi
  if [[ "$(type -t openclaw_is_wsl || true)" != "function" ]]; then
    return 1
  fi
  if ! openclaw_is_wsl; then
    return 1
  fi
  if [[ "$(type -t openclaw_has_powershell || true)" != "function" ]]; then
    return 1
  fi
  if ! openclaw_has_powershell; then
    return 1
  fi
  if [[ "$server_on_windows" != "true" ]]; then
    return 1
  fi
  ps_script="$SCRIPT_DIR/start-server-bg.ps1"
  if [[ ! -f "$ps_script" ]]; then
    return 1
  fi
  ps_script_win="$(wslpath -w "$ps_script")"
  bind_host="0.0.0.0"
  PS_ARGS=(
    -NoProfile -ExecutionPolicy Bypass -File "$ps_script_win"
    -BindHost "$bind_host" -Port "$server_port" -Model "$model" -Device "${device:-directml}" -Engine "$engine"
  )
  if [[ -n "${OPENCLAW_WIN_PYTHON:-}" ]]; then
    PS_ARGS+=(-PythonPath "${OPENCLAW_WIN_PYTHON}")
  fi
  powershell.exe "${PS_ARGS[@]}" >/dev/null 2>&1 || true
  return 0
}

try_server_transcribe() {
  local input_path="$1"
  local model_name="$2"
  local task="$3"

  if ! command -v python3 >/dev/null 2>&1; then
    return 1
  fi

  local health_json
  health_json="$(curl -s --connect-timeout 2 "$server_url/health" || true)"
  if [[ -z "$health_json" ]]; then
    return 1
  fi
  local server_engine
  if ! server_engine="$(printf '%s' "$health_json" | python3 - <<'PY'
import json,sys
try:
    data = json.load(sys.stdin)
    print((data.get("engine") or "").strip())
except Exception:
    pass
PY
  )"; then
    server_engine=""
  fi
  if [[ "$engine" != "auto" && -n "$engine" && "$engine" != "$server_engine" ]]; then
    return 1
  fi

  local send_path="$input_path"
  if [[ "$server_on_windows" == "true" ]]; then
    send_path="$(wslpath -w "$input_path")"
  fi

  local payload
  if ! payload="$(python3 - "$send_path" "$model_name" "$task" <<'PY'
import json,sys
path, model, task = sys.argv[1:4]
payload = {"path": path, "model": model, "task": task}
print(json.dumps(payload))
PY
  )"; then
    return 1
  fi

  local resp_file
  resp_file="$(mktemp)"
  local http_code
  http_code="$(curl -s -w "%{http_code}" -o "$resp_file" \
    -X POST "$server_url/transcribe" \
    -H "Content-Type: application/json" \
    -d "$payload" || true)"

  if [[ "$http_code" != "200" ]]; then
    rm -f "$resp_file"
    return 1
  fi

  local text
  if ! text="$(python3 - "$resp_file" <<'PY'
import json,sys
path = sys.argv[1]
try:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    print((data.get("text") or "").strip())
except Exception:
    pass
PY
  )"; then
    rm -f "$resp_file"
    return 1
  fi
  rm -f "$resp_file"

  if [[ -z "$text" ]]; then
    return 1
  fi

  echo "$text"
  return 0
}

# Create temp directory for whisper output
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

# Get base filename without extension for finding output
base_name=$(basename "$in")
base_name_no_ext="${base_name%.*}"

if [[ "$should_try_server" == "true" ]]; then
  start_warm_server || true
  if try_server_transcribe "$in" "$model" "translate"; then
    exit 0
  fi
fi

if [[ "${device,,}" == "directml" || "${device,,}" == "dml" ]]; then
  if ! command -v powershell.exe &>/dev/null; then
    echo "Error: powershell.exe not found. DirectML path requires Windows PowerShell." >&2
    exit 1
  fi

  ps_script="$SCRIPT_DIR/transcribe-directml.ps1"
  if [[ ! -f "$ps_script" ]]; then
    echo "Error: Missing PowerShell script: $ps_script" >&2
    exit 1
  fi
  ps_script_win="$(wslpath -w "$ps_script")"

  win_in=$(wslpath -w "$in")
  PS_ARGS=(
    -NoProfile -ExecutionPolicy Bypass -File "$ps_script_win"
    -AudioPath "$win_in" -Model "$model" -Task "translate" -Engine "$engine"
  )
  if [[ -n "${OPENCLAW_WIN_PYTHON:-}" ]]; then
    PS_ARGS+=(-PythonPath "${OPENCLAW_WIN_PYTHON}")
  fi
  powershell.exe "${PS_ARGS[@]}"
  exit $?
fi

# Check whisper is available
if ! command -v whisper &>/dev/null; then
  echo "Error: whisper not found. Install with: pip install openai-whisper" >&2
  exit 1
fi

# Run whisper with --task translate (X->English)
whisper_args=(
  "$in"
  --model "$model"
  --task translate
  --output_format txt
  --output_dir "$tmp_dir"
)

# Add device if specified
if [[ -n "$device" ]]; then
  whisper_args+=(--device "$device")
fi

# Run whisper
if ! whisper "${whisper_args[@]}" >/dev/null 2>&1; then
  echo "Error: Whisper translation failed (model=$model)" >&2
  exit 1
fi

# Find the output file
txt_file="$tmp_dir/${base_name_no_ext}.txt"

if [[ ! -f "$txt_file" ]]; then
  echo "Error: Translation output not found" >&2
  exit 1
fi

# Read and output the translated text
transcript=$(cat "$txt_file")

if [[ -z "$transcript" ]]; then
  echo "Error: Translation is empty" >&2
  exit 1
fi

echo "$transcript"
