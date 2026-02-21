#!/usr/bin/env bash
set -euo pipefail

openclaw_is_wsl() {
  if [[ -f /proc/version ]]; then
    grep -qi "microsoft" /proc/version
    return $?
  fi
  return 1
}

openclaw_has_powershell() {
  command -v powershell.exe >/dev/null 2>&1
}

openclaw_device_default() {
  if [[ -n "${OPENCLAW_DEVICE:-}" ]]; then
    echo "${OPENCLAW_DEVICE}"
    return 0
  fi
  if openclaw_is_wsl && openclaw_has_powershell; then
    echo "directml"
    return 0
  fi
  echo "auto"
}

openclaw_win_python() {
  if [[ -n "${OPENCLAW_WIN_PYTHON:-}" ]]; then
    echo "${OPENCLAW_WIN_PYTHON}"
    return 0
  fi
  echo ""
}

openclaw_windows_host() {
  if openclaw_is_wsl; then
    local gw=""
    if command -v ip >/dev/null 2>&1; then
      gw="$(ip route 2>/dev/null | awk '/default/ {print $3; exit}')"
    fi
    if [[ -z "$gw" && -f /etc/resolv.conf ]]; then
      gw="$(awk '/^nameserver/ {print $2; exit}' /etc/resolv.conf)"
    fi
    if [[ -n "$gw" ]]; then
      echo "$gw"
      return 0
    fi
  fi
  echo "127.0.0.1"
}
