#!/usr/bin/env bash
set -euo pipefail

# Backwards-compatible wrapper: generate a WhatsApp-ready OGG/Opus
# using the warm server (auto-start) path.

text="${1:-Hello! This is Pocket TTS.}"
out="${2:-/tmp/pocket-tts-reply.ogg}"

script_path="$(readlink -f "${BASH_SOURCE[0]}")"
here="$(cd -- "$(dirname -- "$script_path")" && pwd)"
exec "$here/voice-note-pocket-tts.sh" --text "$text" --out "$out"
