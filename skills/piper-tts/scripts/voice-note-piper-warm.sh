#!/usr/bin/env bash
set -euo pipefail

# Piper TTS voice-note generator (WARM MODE) for Clawdbot
# - Auto-starts warm Piper TTS server on demand
# - Calls local /tts endpoint for fast synthesis
# - Converts WAV to OGG/Opus for WhatsApp/Telegram voice notes
#
# Usage:
#   voice-note-piper-warm.sh --text "hello" --out /tmp/reply.ogg [--emit-tag]
#   voice-note-piper-warm.sh --text-file /path/reply.txt --out /tmp/reply.ogg [--emit-tag]

usage() {
  cat >&2 <<'EOF'
Usage:
  voice-note-piper-warm.sh --text "hello" --out /tmp/reply.ogg [--emit-tag]
  voice-note-piper-warm.sh --text-file /path/reply.txt --out /tmp/reply.ogg [--emit-tag]

Options:
  --text         Text to speak
  --text-file    Path to text file
  --out          Output .ogg path (default: /tmp/piper-reply.ogg)
  --emit-tag     Print [[audio_as_voice]] + MEDIA:<out>

This script auto-starts the Piper warm server on demand.
First request may take longer while model loads.

Env:
  PIPER_DEVICE (optional): directml, cuda, cpu, auto
  PIPER_VOICE_ID (optional): DirectML server voice name
  OPENCLAW_DEVICE (optional): global device hint
  OPENCLAW_WIN_PYTHON (optional): Windows Python path for DirectML
EOF
  exit 2
}

text=""
text_file=""
out=""
emit_tag=false
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
COMMON_DEVICE="$SKILLS_ROOT/_common/device.sh"
if [[ -f "$COMMON_DEVICE" ]]; then
  # shellcheck source=/dev/null
  source "$COMMON_DEVICE"
fi
device="${PIPER_DEVICE:-${OPENCLAW_DEVICE:-}}"
if [[ -z "$device" && "$(type -t openclaw_device_default || true)" == "function" ]]; then
  device="$(openclaw_device_default)"
fi
if [[ "${device,,}" == "auto" && "$(type -t openclaw_device_default || true)" == "function" ]]; then
  device="$(openclaw_device_default)"
fi
[[ -z "$device" ]] && device="auto"
voice_id="${PIPER_VOICE_ID:-}"
tts_host="${TTS_SERVER_HOST:-localhost}"
tts_port="${TTS_SERVER_PORT:-8099}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --text)
      text="${2:-}"; shift 2;;
    --text-file)
      text_file="${2:-}"; shift 2;;
    --out)
      out="${2:-}"; shift 2;;
    --emit-tag)
      emit_tag=true; shift 1;;
    -h|--help)
      usage;;
    *)
      echo "Unknown arg: $1" >&2
      usage;;
  esac
done

if [[ -n "$text" && -n "$text_file" ]]; then
  echo "Use --text or --text-file, not both." >&2
  exit 1
fi

if [[ -z "$text" && -z "$text_file" ]]; then
  usage
fi

if [[ -n "$text_file" ]]; then
  if [[ ! -f "$text_file" ]]; then
    echo "Missing text file: $text_file" >&2
    exit 1
  fi
  text="$(cat "$text_file")"
fi

if [[ -z "${text//[[:space:]]/}" ]]; then
  echo "Empty text." >&2
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "Missing curl on PATH." >&2
  exit 1
fi

script_path="$(readlink -f "${BASH_SOURCE[0]}")"
here="$(cd -- "$(dirname -- "$script_path")" && pwd)"

# shellcheck source=_env.sh
source "$here/_env.sh"

# Default output
if [[ -z "$out" ]]; then
  out="${TMPDIR:-/tmp}/piper-reply.ogg"
fi

# DirectML path via Windows TTS server
if [[ "${device,,}" == "directml" || "${device,,}" == "dml" ]]; then
  if ! command -v powershell.exe >/dev/null 2>&1; then
    echo "Error: powershell.exe not found. DirectML path requires Windows PowerShell." >&2
    exit 1
  fi

  tts_client="$SKILLS_ROOT/tts-server-directml/scripts/tts-client.sh"
  start_ps="$SKILLS_ROOT/tts-server-directml/scripts/start-server-bg.ps1"
  sync_ps="$SKILLS_ROOT/tts-server-directml/scripts/sync-piper-voice.ps1"
  bind_host="$tts_host"
  if [[ "$tts_host" == "localhost" || "$tts_host" == "127.0.0.1" ]]; then
    if [[ "$(type -t openclaw_windows_host || true)" == "function" ]]; then
      tts_host="$(openclaw_windows_host)"
      bind_host="0.0.0.0"
    fi
  fi

  if [[ ! -x "$tts_client" ]]; then
    echo "Error: Missing TTS client: $tts_client" >&2
    exit 1
  fi
  if [[ ! -f "$start_ps" || ! -f "$sync_ps" ]]; then
    echo "Error: Missing Windows TTS server scripts in tts-server-directml." >&2
    exit 1
  fi
  start_ps_win="$(wslpath -w "$start_ps")"
  sync_ps_win="$(wslpath -w "$sync_ps")"

  if [[ -z "$voice_id" ]]; then
    if [[ -z "$PIPER_VOICE_MODEL" ]]; then
      echo "Error: PIPER_VOICE_MODEL or PIPER_VOICE_ID is required for DirectML." >&2
      exit 1
    fi
    voice_id="$(basename "$PIPER_VOICE_MODEL" .onnx)"

    voice_config="${PIPER_VOICE_CONFIG:-}"
    if [[ -z "$voice_config" && -f "${PIPER_VOICE_MODEL}.json" ]]; then
      voice_config="${PIPER_VOICE_MODEL}.json"
    fi
    if [[ -z "$voice_config" || ! -f "$voice_config" ]]; then
      echo "Error: PIPER_VOICE_CONFIG missing for DirectML (expected ${PIPER_VOICE_MODEL}.json)." >&2
      exit 1
    fi

    win_model=$(wslpath -w "$PIPER_VOICE_MODEL")
    win_config=$(wslpath -w "$voice_config")
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$sync_ps_win" \
      -ModelPath "$win_model" -ConfigPath "$win_config" -VoiceName "$voice_id" >/dev/null
  fi

  if ! curl -s --connect-timeout 2 "http://${tts_host}:${tts_port}/health" >/dev/null 2>&1; then
    echo "Starting Windows TTS server (DirectML)..." >&2
    PS_ARGS=( -NoProfile -ExecutionPolicy Bypass -File "$start_ps_win" -BindHost "$bind_host" -Port "$tts_port" -DefaultModel "piper" -Device "directml" )
    if [[ -n "${OPENCLAW_WIN_PYTHON:-}" ]]; then
      PS_ARGS+=( -PythonPath "${OPENCLAW_WIN_PYTHON}" )
    fi
    powershell.exe "${PS_ARGS[@]}"
  fi

  if $emit_tag; then
    "$tts_client" --text "$text" --out "$out" --model piper --voice "$voice_id" --format ogg --server "$tts_host" --port "$tts_port" --emit-tag
  else
    "$tts_client" --text "$text" --out "$out" --model piper --voice "$voice_id" --format ogg --server "$tts_host" --port "$tts_port"
  fi
  exit $?
fi

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "Missing ffmpeg on PATH." >&2
  exit 1
fi

# Ensure server is running (auto-start)
"$here/server-start.sh" >/dev/null 2>&1 || {
  echo "Failed to start Piper server. Check PIPER_VOICE_MODEL env var." >&2
  exit 1
}

tmpdir="${TMPDIR:-/tmp}"
req_wav="$tmpdir/piper-warm-req-$$.wav"
trap 'rm -f "$req_wav"' EXIT

# Normalize text for TTS (strip markdown, URLs, etc.)
normalize_for_tts() {
  python3 - <<'PY'
import re
import sys
import unicodedata

text = sys.stdin.read()
if not text:
    print("")
    raise SystemExit(0)

# Drop fenced code blocks and inline code
text = re.sub(r"```.*?```", " ", text, flags=re.S)
text = re.sub(r"`[^`]+`", " ", text)

# Convert markdown links [text](url) -> text
text = re.sub(r"\[([^\]]+)\]\([^\)]+\)", r"\1", text)

# Drop raw URLs
text = re.sub(r"https?://\S+", " ", text)

# Strip common markdown markers
text = text.replace("**", "").replace("__", "")
text = re.sub(r"(?m)^\s*[-*+>]+\s*", "", text)
text = re.sub(r"[\[\]{}<>|`~#*_=]", " ", text)

# Normalize dashes
text = text.replace("—", " ").replace("–", " ")
text = re.sub(r"(?<=\w)-(?=\w)", " ", text)

# Remove emoji and symbols
text = "".join(ch for ch in text if unicodedata.category(ch) != "So")

# Convert newlines to sentence breaks
text = re.sub(r"[\r\n]+", ". ", text)
text = re.sub(r"[.!?]{2,}", ".", text)

# Collapse whitespace
text = re.sub(r"\s+", " ", text).strip()
print(text)
PY
}

# Normalize text
normalized="$(printf '%s' "$text" | normalize_for_tts || true)"
if [[ -n "${normalized// }" ]]; then
  text="$normalized"
fi

# Truncate if too long
max_chars="${PIPER_MAX_CHARS:-6000}"
text_len=${#text}
if [[ "$text_len" -gt "$max_chars" ]]; then
  text="${text:0:$max_chars}"
fi

# Call warm server
http_code=$(curl -sS -w '%{http_code}' \
  -X POST "$PIPER_TTS_BASE_URL/tts" \
  -F "text=$text" \
  -o "$req_wav")

if [[ "$http_code" != "200" ]]; then
  echo "Piper server returned HTTP $http_code" >&2
  # Try to read error from response
  if [[ -f "$req_wav" ]]; then
    cat "$req_wav" >&2 || true
  fi
  exit 1
fi

if [[ ! -s "$req_wav" ]]; then
  echo "Piper server returned empty audio." >&2
  exit 1
fi

mkdir -p "$(dirname "$out")"

# Convert WAV -> OGG/Opus for WhatsApp/Telegram voice notes
ffmpeg -y -hide_banner -loglevel error \
  -i "$req_wav" \
  -c:a libopus \
  -b:a 32k \
  -vbr on \
  -application voip \
  "$out"

if [[ ! -s "$out" ]]; then
  echo "Failed to write output: $out" >&2
  exit 1
fi

if $emit_tag; then
  echo "[[audio_as_voice]]"
  echo "MEDIA:$out"
else
  echo "$out"
fi
