#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
COMMON_DEVICE="$SKILLS_ROOT/_common/device.sh"
if [[ -f "$COMMON_DEVICE" ]]; then
  # shellcheck source=/dev/null
  source "$COMMON_DEVICE"
fi

usage() {
  cat >&2 <<'EOF'
Usage:
  voice-note-piper.sh --text "hello" --out /tmp/reply.ogg [--emit-tag]
  voice-note-piper.sh --text-file /path/reply.txt --out /tmp/reply.ogg [--emit-tag]

Prereqs:
- piper (Rhasspy) installed and accessible
- PIPER_VOICE_MODEL set to a Piper .onnx voice model path
- ffmpeg installed

Env:
- PIPER_BIN (default: piper)
- PIPER_VOICE_MODEL (required)
- PIPER_VOICE_CONFIG (optional)
- PIPER_VOICE_ID (optional, DirectML server voice name)
- PIPER_SPEAKER (optional)
- PIPER_LENGTH_SCALE (default: 1.0)
- PIPER_NOISE_SCALE (default: 0.667)
- PIPER_NOISE_W (default: 0.8)
- PIPER_MAX_CHARS (default: 6000)
- PIPER_TTS_NORMALIZE (default: 1)
- PIPER_TTS_REPLACE (optional): "from=to;from2=to2"
- PIPER_TTS_REPLACE_FILE (optional): path to JSON or .env-style key=value list
- PIPER_DEVICE (optional): directml, cuda, cpu, auto
- OPENCLAW_DEVICE (optional): global device hint
- OPENCLAW_WIN_PYTHON (optional): Windows Python path for DirectML

Output:
- If --emit-tag is set, prints:
    [[audio_as_voice]]
    MEDIA:/path/to/out.ogg
- Otherwise prints the output path.
EOF
  exit 2
}

text=""
text_file=""
out=""
emit_tag=false

tmpdir="${TMPDIR:-/tmp}"
piper_bin="${PIPER_BIN:-piper}"
voice_model="${PIPER_VOICE_MODEL:-}"
voice_config="${PIPER_VOICE_CONFIG:-}"

# Optional per-language overrides (auto-detected from Unicode script).
voice_model_hi="${PIPER_VOICE_MODEL_HI:-}"
voice_config_hi="${PIPER_VOICE_CONFIG_HI:-}"
voice_model_te="${PIPER_VOICE_MODEL_TE:-}"
voice_config_te="${PIPER_VOICE_CONFIG_TE:-}"
voice_model_ml="${PIPER_VOICE_MODEL_ML:-}"
voice_config_ml="${PIPER_VOICE_CONFIG_ML:-}"
voice_model_kn="${PIPER_VOICE_MODEL_KN:-}"
voice_config_kn="${PIPER_VOICE_CONFIG_KN:-}"
speaker="${PIPER_SPEAKER:-}"
length_scale="${PIPER_LENGTH_SCALE:-1.0}"
noise_scale="${PIPER_NOISE_SCALE:-0.667}"
noise_w="${PIPER_NOISE_W:-0.8}"
max_chars="${PIPER_MAX_CHARS:-6000}"
normalize_text="${PIPER_TTS_NORMALIZE:-1}"
replace_spec="${PIPER_TTS_REPLACE:-}"
replace_file="${PIPER_TTS_REPLACE_FILE:-}"
voice_id="${PIPER_VOICE_ID:-}"
device="${PIPER_DEVICE:-${OPENCLAW_DEVICE:-}}"
if [[ -z "$device" && "$(type -t openclaw_device_default || true)" == "function" ]]; then
  device="$(openclaw_device_default)"
fi
if [[ "${device,,}" == "auto" && "$(type -t openclaw_device_default || true)" == "function" ]]; then
  device="$(openclaw_device_default)"
fi
[[ -z "$device" ]] && device="auto"
tts_host="${TTS_SERVER_HOST:-localhost}"
tts_port="${TTS_SERVER_PORT:-8099}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --text)
      text="${2:-}"
      shift 2
      ;;
    --text-file)
      text_file="${2:-}"
      shift 2
      ;;
    --out)
      out="${2:-}"
      shift 2
      ;;
    --emit-tag)
      emit_tag=true
      shift 1
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "Unknown arg: $1" >&2
      usage
      ;;
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
    echo "Text file not found: $text_file" >&2
    exit 1
  fi
  text="$(cat "$text_file")"
fi

normalize_for_tts() {
  python3 - <<'PY'
import json
import os
import re
import sys
import unicodedata
from pathlib import Path

text = sys.stdin.read()
if not text:
    print("")
    raise SystemExit(0)

def load_replacements():
    rules = []
    def add_pair(src, dst):
        src = str(src).strip()
        dst = str(dst).strip()
        if not src:
            return
        rules.append((src, dst))

    file_path = os.getenv("PIPER_TTS_REPLACE_FILE", "").strip()
    if file_path:
        path = Path(file_path)
        if path.is_file():
            if path.suffix.lower() == ".json":
                try:
                    data = json.loads(path.read_text())
                    if isinstance(data, dict):
                        for k, v in data.items():
                            add_pair(k, v)
                except Exception:
                    pass
            else:
                for line in path.read_text().splitlines():
                    line = line.strip()
                    if not line or line.startswith("#"):
                        continue
                    if "=" in line:
                        src, dst = line.split("=", 1)
                        add_pair(src, dst)

    env_spec = os.getenv("PIPER_TTS_REPLACE", "")
    for pair in env_spec.split(";"):
        if "=" not in pair:
            continue
        src, dst = pair.split("=", 1)
        add_pair(src, dst)

    return rules

def apply_replacements(text, rules):
    for src, dst in rules:
        if re.fullmatch(r"[A-Za-z0-9_]+", src):
            text = re.sub(rf"\\b{re.escape(src)}\\b", dst, text)
        else:
            text = text.replace(src, dst)
    return text

# Apply custom pronunciations before normalization.
replacements = load_replacements()
if replacements:
    text = apply_replacements(text, replacements)

# Drop fenced code blocks and inline code.
text = re.sub(r"```.*?```", " ", text, flags=re.S)
text = re.sub(r"`[^`]+`", " ", text)

# Convert markdown links [text](url) -> text.
text = re.sub(r"\\[([^\\]]+)\\]\\([^\\)]+\\)", r"\\1", text)

# Drop raw URLs.
text = re.sub(r"https?://\\S+", " ", text)

# Strip common markdown markers.
text = text.replace("**", "").replace("__", "")
text = re.sub(r"(?m)^\\s*[-*+>]+\\s*", "", text)
text = re.sub(r"[\\[\\]{}<>|`~#*_=]", " ", text)

# Normalize dashes and hyphenated tokens.
text = text.replace("—", " ").replace("–", " ")
text = re.sub(r"(?<=\\w)-(?=\\w)", " ", text)

# Remove emoji and symbol characters that read poorly.
text = "".join(ch for ch in text if unicodedata.category(ch) != "So")

# Convert newlines to sentence breaks, collapse punctuation.
text = re.sub(r"[\\r\\n]+", ". ", text)
text = re.sub(r"[.!?]{2,}", ".", text)

# Collapse whitespace.
text = re.sub(r"\\s+", " ", text).strip()
print(text)
PY
}

raw_text="$text"
if [[ "$normalize_text" == "1" || "$normalize_text" == "true" ]]; then
  normalized="$(printf '%s' "$text" | normalize_for_tts || true)"
  if [[ -n "${normalized// }" ]]; then
    text="$normalized"
  else
    text="$raw_text"
  fi
fi

if [[ -z "${text// }" ]]; then
  echo "Text is empty." >&2
  exit 1
fi

if ! [[ "$max_chars" =~ ^[0-9]+$ ]] || [[ "$max_chars" -le 0 ]]; then
  echo "Invalid PIPER_MAX_CHARS: $max_chars" >&2
  exit 1
fi

text_len=${#text}
if [[ "$text_len" -gt "$max_chars" ]]; then
  text="${text:0:$max_chars}"
fi

if [[ -z "$out" ]]; then
  out="${tmpdir%/}/voice-reply.ogg"
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
    if [[ -z "$voice_model" ]]; then
      echo "Error: PIPER_VOICE_MODEL or PIPER_VOICE_ID is required for DirectML." >&2
      exit 1
    fi
    if [[ -z "$voice_config" && -f "${voice_model}.json" ]]; then
      voice_config="${voice_model}.json"
    fi
    if [[ -z "$voice_config" || ! -f "$voice_config" ]]; then
      echo "Error: PIPER_VOICE_CONFIG missing for DirectML (expected ${voice_model}.json)." >&2
      exit 1
    fi
    voice_id="$(basename "$voice_model" .onnx)"

    win_model=$(wslpath -w "$voice_model")
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

detect_script_lang() {
  # Returns one of: hi, te, ml, kn, none
  # Uses Unicode ranges for Indic scripts.
  python3 - <<'PY'
import sys
text=sys.stdin.read()
# Quick scan
for ch in text:
    cp=ord(ch)
    if 0x0900 <= cp <= 0x097F:
        print('hi'); sys.exit(0)  # Devanagari
    if 0x0C00 <= cp <= 0x0C7F:
        print('te'); sys.exit(0)  # Telugu
    if 0x0D00 <= cp <= 0x0D7F:
        print('ml'); sys.exit(0)  # Malayalam
    if 0x0C80 <= cp <= 0x0CFF:
        print('kn'); sys.exit(0)  # Kannada
print('none')
PY
}

lang_hint="$(printf '%s' "$text" | detect_script_lang || true)"
case "$lang_hint" in
  hi)
    if [[ -n "$voice_model_hi" ]]; then
      voice_model="$voice_model_hi"
      voice_config="$voice_config_hi"
    fi
    ;;
  te)
    if [[ -n "$voice_model_te" ]]; then
      voice_model="$voice_model_te"
      voice_config="$voice_config_te"
    fi
    ;;
  ml)
    if [[ -n "$voice_model_ml" ]]; then
      voice_model="$voice_model_ml"
      voice_config="$voice_config_ml"
    fi
    ;;
  kn)
    if [[ -n "$voice_model_kn" ]]; then
      voice_model="$voice_model_kn"
      voice_config="$voice_config_kn"
    fi
    ;;
  *)
    ;;
esac

if [[ -z "$voice_model" ]]; then
  echo "Missing PIPER_VOICE_MODEL (path to .onnx voice model)." >&2
  exit 1
fi

if ! command -v "$piper_bin" >/dev/null 2>&1; then
  echo "Missing piper on PATH (or set PIPER_BIN)." >&2
  exit 1
fi

wav_tmp=""
cleanup() {
  if [[ -n "$wav_tmp" ]]; then
    rm -f "$wav_tmp" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

wav_tmp="$(mktemp -p "$tmpdir" piper-reply-XXXXXX.wav)"

# Piper reads text from stdin.
# CLI flags vary slightly across builds; these are common and safe.
# If your piper build requires a config json, set PIPER_VOICE_CONFIG.
piper_args=(
  --model "$voice_model"
  --output_file "$wav_tmp"
  --quiet
)

if [[ -n "$voice_config" ]]; then
  piper_args+=(--config "$voice_config")
fi

if [[ -n "$speaker" ]]; then
  piper_args+=(--speaker "$speaker")
fi

# Optional controls
piper_args+=(--length_scale "$length_scale" --noise_scale "$noise_scale" --noise_w "$noise_w")

# IMPORTANT: keep stdout clean for Clawdbot (only MEDIA tags).
# Piper reads text from stdin and writes WAV to --output_file.
printf '%s' "$text" | "$piper_bin" "${piper_args[@]}" >/dev/null

# Convert to WhatsApp-friendly OGG/Opus.
# -application voip improves speech quality for low bitrates.
ffmpeg -y -hide_banner -loglevel error \
  -i "$wav_tmp" \
  -c:a libopus -application voip -b:a 32k \
  "$out"

if [[ "${PIPER_TTS_DEBUG:-}" == "1" || "${PIPER_TTS_DEBUG:-}" == "true" ]]; then
  debug_dir="${PIPER_TTS_DEBUG_DIR:-$HOME/.openclaw/media/outbound}"
  mkdir -p "$debug_dir" 2>/dev/null || true
  ts="$(date -u +%Y%m%dT%H%M%SZ)"
  debug_file="$debug_dir/piper-tts-$ts.log"
  {
    echo "ts=$ts"
    echo "lang_hint=${lang_hint:-}"
    echo "voice_model=$voice_model"
    echo "voice_config=${voice_config:-}"
    echo "text_len=${#text}"
    echo "out=$out"
    ls -lh "$out" 2>/dev/null || true
  } >"$debug_file" 2>/dev/null || true
fi

if $emit_tag; then
  printf '[[audio_as_voice]]\nMEDIA:%s\n' "$out"
else
  printf '%s\n' "$out"
fi
