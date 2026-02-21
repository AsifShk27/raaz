#!/usr/bin/env bash
set -euo pipefail

# Pocket TTS voice-note generator for Clawdbot
# - Auto-starts a warm Pocket TTS server on demand
# - Calls the local /tts endpoint (streaming audio/wav)
# - Converts to OGG/Opus for WhatsApp/Telegram voice notes
#
# Usage:
#   voice-note-pocket-tts.sh --text "hello" --out /tmp/reply.ogg [--voice alba] [--bitrate 32k] [--emit-tag]
#   voice-note-pocket-tts.sh --text-file /path/reply.txt --out /tmp/reply.ogg [--voice alba]

usage() {
  cat >&2 <<'EOF'
Usage:
  voice-note-pocket-tts.sh --text "hello" --out /tmp/reply.ogg [--voice alba] [--bitrate 32k]
  voice-note-pocket-tts.sh --text-file /path/reply.txt --out /tmp/reply.ogg [--voice alba] [--bitrate 32k]
  voice-note-pocket-tts.sh --text "hello" --emit-tag

Options:
  --text         Text to speak
  --text-file    Path to text file
  --out          Output .ogg path (required unless --emit-tag with default)
  --voice        Voice preset or URL (mapped to voice_url). Default: alba
  --voice-wav    Path to a WAV file to clone (uploads as voice_wav)
  --bitrate      Opus bitrate (default: 32k)
  --emit-tag     Print [[audio_as_voice]] + MEDIA:<out>
EOF
  exit 2
}

text=""
text_file=""
out=""
voice=""
voice_wav=""
bitrate="32k"
emit_tag=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --text)
      text="${2:-}"; shift 2;;
    --text-file)
      text_file="${2:-}"; shift 2;;
    --out)
      out="${2:-}"; shift 2;;
    --voice)
      voice="${2:-}"; shift 2;;
    --voice-wav)
      voice_wav="${2:-}"; shift 2;;
    --bitrate)
      bitrate="${2:-}"; shift 2;;
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

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "Missing ffmpeg on PATH." >&2
  exit 1
fi

script_path="$(readlink -f "${BASH_SOURCE[0]}")"
here="$(cd -- "$(dirname -- "$script_path")" && pwd)"
# shellcheck source=_env.sh
source "$here/_env.sh"

# Default output
if [[ -z "$out" ]]; then
  out="${TMPDIR:-/tmp}/pocket-tts-reply.ogg"
fi

# Ensure server is running (auto-start)
"$here/server-start.sh" >/dev/null

tmpdir="${TMPDIR:-/tmp}"
req_wav="$tmpdir/pocket-tts-req-$$.wav"
trap 'rm -f "$req_wav"' EXIT

# Build curl form args
curl_args=(
  -fsS
  -X POST
  "$POCKET_TTS_BASE_URL/tts"
  -o "$req_wav"
  -F "text=$text"
)

if [[ -n "$voice" ]]; then
  curl_args+=( -F "voice_url=$voice" )
else
  curl_args+=( -F "voice_url=$POCKET_TTS_DEFAULT_VOICE" )
fi

if [[ -n "$voice_wav" ]]; then
  if [[ ! -f "$voice_wav" ]]; then
    echo "Missing voice wav: $voice_wav" >&2
    exit 1
  fi
  curl_args+=( -F "voice_wav=@$voice_wav" )
fi

curl "${curl_args[@]}" >/dev/null

if [[ ! -s "$req_wav" ]]; then
  echo "Pocket TTS returned empty audio." >&2
  exit 1
fi

mkdir -p "$(dirname "$out")"

# Convert WAV -> OGG/Opus
ffmpeg -y -hide_banner -loglevel error \
  -i "$req_wav" \
  -c:a libopus \
  -b:a "$bitrate" \
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
