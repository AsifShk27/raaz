#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
COMMON_DEVICE="$SKILLS_ROOT/_common/device.sh"
if [[ -f "$COMMON_DEVICE" ]]; then
  # shellcheck source=/dev/null
  source "$COMMON_DEVICE"
fi

START_PS="$SCRIPT_DIR/start-server-detached.ps1"
STOP_WSL="$SCRIPT_DIR/stop-server-wsl.sh"

EMBEDDINGS_PORT="${EMBEDDINGS_PORT:-8124}"
EMBEDDINGS_MODEL="${EMBEDDINGS_MODEL:-BAAI/bge-base-en-v1.5}"
EMBEDDINGS_DEVICE="${EMBEDDINGS_DEVICE:-directml}"
EMBEDDINGS_POOLING="${EMBEDDINGS_POOLING:-cls}"
EMBEDDINGS_BIND_HOST="${EMBEDDINGS_BIND_HOST:-0.0.0.0}"
EMBEDDINGS_WIN_PYTHON="${EMBEDDINGS_WIN_PYTHON:-${OPENCLAW_WIN_PYTHON:-}}"
WATCHDOG_INTERVAL_SECONDS="${EMBEDDINGS_WATCHDOG_INTERVAL_SECONDS:-15}"
WATCHDOG_REQUIRE_DEVICE="${EMBEDDINGS_WATCHDOG_REQUIRE_DEVICE:-directml}"
WATCHDOG_HEALTH_TIMEOUT_SECONDS="${EMBEDDINGS_WATCHDOG_HEALTH_TIMEOUT_SECONDS:-3}"
STOP_ON_EXIT="${EMBEDDINGS_STOP_ON_EXIT:-0}"

log() {
  printf '[embeddings-watchdog] %s\n' "$*" >&2
}

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

resolve_windows_host() {
  if [[ -n "${EMBEDDINGS_WINDOWS_HOST:-}" ]]; then
    printf '%s\n' "$EMBEDDINGS_WINDOWS_HOST"
    return 0
  fi
  if [[ "$(type -t openclaw_windows_host || true)" == "function" ]]; then
    local host
    host="$(openclaw_windows_host 2>/dev/null || true)"
    if [[ -n "$host" ]]; then
      printf '%s\n' "$host"
      return 0
    fi
  fi
  if command -v /usr/sbin/ip >/dev/null 2>&1; then
    local route_host
    route_host="$(/usr/sbin/ip route 2>/dev/null | awk '/^default / {print $3; exit}')"
    if [[ -n "$route_host" ]]; then
      printf '%s\n' "$route_host"
      return 0
    fi
  fi
  if [[ -r /etc/resolv.conf ]]; then
    local ns_host
    ns_host="$(awk '/^nameserver / {print $2; exit}' /etc/resolv.conf || true)"
    if [[ -n "$ns_host" ]]; then
      printf '%s\n' "$ns_host"
      return 0
    fi
  fi
  printf '127.0.0.1\n'
}

start_server() {
  if [[ ! -f "$START_PS" ]]; then
    log "start script missing: $START_PS"
    return 1
  fi
  if ! command -v powershell.exe >/dev/null 2>&1; then
    log "powershell.exe not found; cannot start DirectML embeddings server."
    return 1
  fi

  local start_ps_win
  start_ps_win="$(wslpath -w "$START_PS")"
  local args=(
    -NoProfile -ExecutionPolicy Bypass -File "$start_ps_win"
    -BindHost "$EMBEDDINGS_BIND_HOST"
    -Port "$EMBEDDINGS_PORT"
    -Model "$EMBEDDINGS_MODEL"
    -Device "$EMBEDDINGS_DEVICE"
    -Pooling "$EMBEDDINGS_POOLING"
  )
  if [[ -n "$EMBEDDINGS_WIN_PYTHON" ]]; then
    args+=( -PythonPath "$EMBEDDINGS_WIN_PYTHON" )
  fi
  powershell.exe "${args[@]}" >/tmp/openclaw-embeddings-watchdog-start.log 2>&1 || return 1
  return 0
}

stop_server() {
  if [[ -x "$STOP_WSL" ]]; then
    "$STOP_WSL" >/tmp/openclaw-embeddings-watchdog-stop.log 2>&1 || true
  fi
}

read_json_field() {
  local json="$1"
  local field="$2"
  python3 - "$field" <<'PY' <<<"$json"
import json
import sys

field = sys.argv[1]
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(1)

value = data.get(field)
if value is None:
    sys.exit(1)
print(value)
PY
}

health_json() {
  local host
  host="$(resolve_windows_host)"
  curl -s --connect-timeout 2 --max-time "$WATCHDOG_HEALTH_TIMEOUT_SECONDS" "http://${host}:${EMBEDDINGS_PORT}/health" || true
}

ensure_server() {
  local health
  health="$(health_json)"
  if [[ -z "$health" ]]; then
    log "health check failed; starting DirectML embeddings server."
    start_server || log "start attempt failed."
    return 0
  fi

  if [[ -n "$WATCHDOG_REQUIRE_DEVICE" ]]; then
    local current_device
    current_device="$(read_json_field "$health" "device" || true)"
    if [[ -n "$current_device" && "${current_device,,}" != "${WATCHDOG_REQUIRE_DEVICE,,}" ]]; then
      log "device drift detected (${current_device}); restarting for ${WATCHDOG_REQUIRE_DEVICE}."
      stop_server
      start_server || log "restart attempt failed."
      return 0
    fi
  fi
}

stop_requested=false
on_term() {
  stop_requested=true
}

trap on_term INT TERM

log "watchdog started (port=${EMBEDDINGS_PORT}, model=${EMBEDDINGS_MODEL}, device=${EMBEDDINGS_DEVICE}, pooling=${EMBEDDINGS_POOLING})"
ensure_server

while true; do
  if [[ "$stop_requested" == "true" ]]; then
    break
  fi
  ensure_server
  sleep "$WATCHDOG_INTERVAL_SECONDS"
done

if is_true "$STOP_ON_EXIT"; then
  log "stop requested; stopping Windows embeddings server."
  stop_server
fi

log "watchdog exiting."
