#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

COMMON_DEVICE="$SKILLS_ROOT/_common/device.sh"
if [[ -f "$COMMON_DEVICE" ]]; then
  # shellcheck source=/dev/null
  source "$COMMON_DEVICE"
fi

usage() {
  cat >&2 <<'EOF'
Usage:
  tts-router.sh --text "hello" --out /tmp/reply.ogg [--emit-tag]
  tts-router.sh --text-file /path/reply.txt --out /tmp/reply.ogg

Options:
  --text         Text to synthesize
  --text-file    Path to text file
  --out          Output file (required unless --emit-tag)
  --emit-tag     Print [[audio_as_voice]] + MEDIA:<out>
EOF
  exit 2
}

text=""
text_file=""
out=""
emit_tag=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --text) text="${2:-}"; shift 2;;
    --text-file) text_file="${2:-}"; shift 2;;
    --out) out="${2:-}"; shift 2;;
    --emit-tag) emit_tag=true; shift 1;;
    -h|--help) usage;;
    *) echo "Unknown arg: $1" >&2; usage;;
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
  [[ -f "$text_file" ]] || { echo "Missing text file: $text_file" >&2; exit 1; }
  text="$(cat "$text_file")"
fi

if [[ -z "${text//[[:space:]]/}" ]]; then
  echo "Empty text." >&2
  exit 1
fi

if [[ -z "$out" ]]; then
  out="/tmp/tts-reply-$(date +%s).ogg"
fi

device="${OPENCLAW_DEVICE:-}"
if [[ -z "$device" && "$(type -t openclaw_device_default || true)" == "function" ]]; then
  device="$(openclaw_device_default)"
fi
[[ -z "$device" ]] && device="auto"

primary="${OPENCLAW_TTS_PRIMARY:-qwen3-warm}"
fallback="${OPENCLAW_TTS_FALLBACK:-pocket}"

qwen3_script="$SKILLS_ROOT/qwen3-tts/scripts/voice-note-qwen3-tts-warm.sh"
pocket_script="$SKILLS_ROOT/pocket-tts/scripts/voice-note-pocket-tts.sh"

run_qwen3() {
  [[ -x "$qwen3_script" ]] || return 1
  if $emit_tag; then
    "$qwen3_script" --text "$text" --out "$out" --emit-tag
  else
    "$qwen3_script" --text "$text" --out "$out"
  fi
}

run_pocket() {
  [[ -x "$pocket_script" ]] || return 1
  if $emit_tag; then
    "$pocket_script" --text "$text" --out "$out" --emit-tag
  else
    "$pocket_script" --text "$text" --out "$out"
  fi
}

set +e
if [[ "$primary" == "qwen3-warm" ]]; then
  OPENCLAW_DEVICE="$device" run_qwen3
  rc=$?
  if [[ $rc -eq 0 && -s "$out" ]]; then
    exit 0
  fi
  echo "[tts-router] Qwen3 warm failed, falling back to Pocket TTS." >&2
  run_pocket
  rc=$?
  [[ $rc -eq 0 && -s "$out" ]] && exit 0
  exit $rc
fi

if [[ "$primary" == "pocket" ]]; then
  run_pocket
  rc=$?
  [[ $rc -eq 0 && -s "$out" ]] && exit 0
  echo "[tts-router] Pocket TTS failed, falling back to Qwen3 warm." >&2
  OPENCLAW_DEVICE="$device" run_qwen3
  rc=$?
  [[ $rc -eq 0 && -s "$out" ]] && exit 0
  exit $rc
fi

echo "[tts-router] Unknown primary: $primary" >&2
exit 1
