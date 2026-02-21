#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage:
  voice-note-chatterbox-warm.sh --text "hello" --out /tmp/reply.ogg [--emit-tag]
  voice-note-chatterbox-warm.sh --text-file /path/reply.txt --out /tmp/reply.ogg [--emit-tag]

Options:
  --text            Text to synthesize
  --text-file       Input text file
  --out             Output OGG file
  --emit-tag        Print [[audio_as_voice]] + MEDIA:<out>
  --audio-prompt    Optional WAV path for voice conditioning
USAGE
  exit 2
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$script_dir/_env.sh"

text=""
text_file=""
out=""
audio_prompt=""
emit_tag=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --text) text="${2:-}"; shift 2 ;;
    --text-file) text_file="${2:-}"; shift 2 ;;
    --out) out="${2:-}"; shift 2 ;;
    --audio-prompt) audio_prompt="${2:-}"; shift 2 ;;
    --emit-tag) emit_tag=true; shift ;;
    -h|--help) usage ;;
    *) echo "Unknown arg: $1" >&2; usage ;;
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

trimmed="${text//[[:space:]]/}"
if [[ -z "$trimmed" ]]; then
  echo "Empty text." >&2
  exit 1
fi

if [[ "${#text}" -gt "$CHATTERBOX_TTS_MAX_CHARS" ]]; then
  echo "[chatterbox-tts] Text length ${#text} exceeds max ${CHATTERBOX_TTS_MAX_CHARS}; truncating." >&2
  text="${text:0:$CHATTERBOX_TTS_MAX_CHARS}"
fi

[[ -n "$out" ]] || out="${TMPDIR:-/tmp}/chatterbox-reply.ogg"
mkdir -p "$(dirname "$out")"

if ! command -v curl >/dev/null 2>&1; then
  echo "Missing curl." >&2
  exit 1
fi
if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "Missing ffmpeg." >&2
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "Missing python3." >&2
  exit 1
fi

"$script_dir/server-start.sh" >/dev/null

tmp_wav="$(mktemp --suffix=.wav)"
trap 'rm -f "$tmp_wav"' EXIT

payload="$(TEXT="$text" AUDIO_PROMPT="$audio_prompt" python3 - <<'PY'
import json
import os

body = {
    "text": os.environ["TEXT"],
}
ap = os.environ.get("AUDIO_PROMPT", "").strip()
if ap:
    body["audio_prompt_path"] = ap
print(json.dumps(body))
PY
)"

curl -fsS -X POST "http://${CHATTERBOX_TTS_HOST}:${CHATTERBOX_TTS_PORT}/tts" \
  -H "Content-Type: application/json" \
  --data "$payload" \
  -o "$tmp_wav"

if [[ ! -s "$tmp_wav" ]]; then
  echo "Chatterbox returned empty audio." >&2
  exit 1
fi

ffmpeg_args=(
  -y
  -hide_banner
  -loglevel error
  -i "$tmp_wav"
  -c:a libopus
  -b:a "$CHATTERBOX_TTS_OUTPUT_BITRATE"
  -vbr on
  -application "$CHATTERBOX_TTS_OUTPUT_APPLICATION"
)

if [[ -n "${CHATTERBOX_TTS_OUTPUT_FILTER:-}" ]]; then
  ffmpeg_args+=( -af "$CHATTERBOX_TTS_OUTPUT_FILTER" )
fi

ffmpeg_args+=( "$out" )
ffmpeg "${ffmpeg_args[@]}"

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
