#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage:
  voice-note.sh --text "hello" --out /tmp/reply.ogg [--voice "Clawd"] [--bitrate 32k] [--allow-env]
  voice-note.sh --text-file /path/reply.txt --out /tmp/reply.ogg [--voice "Clawd"] [--bitrate 32k] [--allow-env]
  voice-note.sh --text "hello" --emit-tag

Notes:
- Requires sag (ElevenLabs TTS) and ffmpeg on PATH.
- Outputs OGG/Opus for voice-note compatibility.
- API key sources (first found):
  - ~/.openclaw/openclaw.json (talk.apiKey or skills.sag.apiKey)
  - ELEVENLABS_API_KEY or SAG_API_KEY env var (only with --allow-env or VOICE_NOTE_ALLOW_ENV=1)
- Voice selection (first found):
  - --voice (supports talk.voiceAliases)
  - ~/.openclaw/openclaw.json (talk.voiceId)
  - ELEVENLABS_VOICE_ID or SAG_VOICE_ID env var (only with --allow-env or VOICE_NOTE_ALLOW_ENV=1)
EOF
  exit 2
}

text=""
text_file=""
out=""
voice=""
bitrate="32k"
# ElevenLabs TTS hard-limit is commonly 5000 chars; keep margin.
max_chars="${VOICE_NOTE_MAX_CHARS:-4800}"
tmpdir="${TMPDIR:-/tmp}"
emit_tag=false
config_path="${OPENCLAW_CONFIG:-$HOME/.openclaw/openclaw.json}"
debug="${VOICE_NOTE_DEBUG:-}"
api_key_source=""
voice_source=""
allow_env=false

if [[ "${VOICE_NOTE_ALLOW_ENV:-}" == "1" || "${VOICE_NOTE_ALLOW_ENV:-}" == "true" ]]; then
  allow_env=true
fi

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
    --voice)
      voice="${2:-}"
      shift 2
      ;;
    --bitrate)
      bitrate="${2:-}"
      shift 2
      ;;
    --max-chars)
      max_chars="${2:-}"
      shift 2
      ;;
    --tmp-dir)
      tmpdir="${2:-}"
      shift 2
      ;;
    --emit-tag)
      emit_tag=true
      shift 1
      ;;
    --allow-env)
      allow_env=true
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

if ! command -v sag >/dev/null 2>&1; then
  echo "Missing sag on PATH." >&2
  exit 1
fi

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "Missing ffmpeg on PATH." >&2
  exit 1
fi

read_config_api_key() {
  local cfg="$1"
  if [[ ! -f "$cfg" ]]; then
    return 1
  fi
  if command -v node >/dev/null 2>&1; then
    local key
    key="$(node -e '
      const fs = require("fs");
      const cfg = process.argv[1];
      if (!fs.existsSync(cfg)) process.exit(1);
      const raw = fs.readFileSync(cfg, "utf8");
      let data = null;
      try {
        const JSON5 = require("json5");
        data = JSON5.parse(raw);
      } catch (err) {
        try {
          data = JSON.parse(raw);
        } catch {
          data = null;
        }
      }
      const key =
        (data && data.talk && data.talk.apiKey) ||
        (data && data.skills && data.skills.sag && data.skills.sag.apiKey) ||
        "";
      if (key) process.stdout.write(String(key));
    ' "$cfg" 2>/dev/null || true)"
    if [[ -n "$key" ]]; then
      if [[ -n "$debug" ]]; then
        echo "debug: node config key len=${#key}" >&2
      fi
      printf '%s' "$key"
      return 0
    fi
    if [[ -n "$debug" ]]; then
      echo "debug: node config key len=0" >&2
    fi
  fi
  if command -v python3 >/dev/null 2>&1; then
    local py_key
    py_key="$(python3 - "$cfg" 2>/dev/null <<'PY' || true
import re
import sys
from pathlib import Path

cfg = Path(sys.argv[1])
if not cfg.exists():
    sys.exit(1)
text = cfg.read_text(encoding="utf-8", errors="ignore")

patterns = [
    r"talk\\s*:\\s*\\{[\\s\\S]*?apiKey\\s*:\\s*['\\\"]([^'\\\"]+)['\\\"]",
    r"skills\\s*:\\s*\\{[\\s\\S]*?sag\\s*:\\s*\\{[\\s\\S]*?apiKey\\s*:\\s*['\\\"]([^'\\\"]+)['\\\"]",
]
for pat in patterns:
    match = re.search(pat, text, re.IGNORECASE)
    if match:
        sys.stdout.write(match.group(1))
        sys.exit(0)
sys.exit(2)
PY
)"
    if [[ -n "$py_key" ]]; then
      if [[ -n "$debug" ]]; then
        echo "debug: python config key len=${#py_key}" >&2
      fi
      printf '%s' "$py_key"
      return 0
    fi
    if [[ -n "$debug" ]]; then
      echo "debug: python config key len=0" >&2
    fi
  fi
  local line
  line="$(grep -m1 -E 'apiKey[[:space:]]*:' "$cfg" 2>/dev/null || true)"
  if [[ -n "$line" ]]; then
    local grep_key
    grep_key="$(printf '%s' "$line" | sed -E "s/.*apiKey[[:space:]]*:[[:space:]]*['\"]([^'\"]+)['\"].*/\1/")"
    if [[ -n "$grep_key" ]]; then
      if [[ -n "$debug" ]]; then
        echo "debug: grep config key len=${#grep_key}" >&2
      fi
      printf '%s' "$grep_key"
      return 0
    fi
    if [[ -n "$debug" ]]; then
      echo "debug: grep config key len=0" >&2
    fi
  fi
}

read_config_voice_id() {
  local cfg="$1"
  if [[ ! -f "$cfg" ]]; then
    return 1
  fi
  if command -v node >/dev/null 2>&1; then
    local vid
    vid="$(node -e '
      const fs = require("fs");
      const cfg = process.argv[1];
      if (!fs.existsSync(cfg)) process.exit(1);
      const raw = fs.readFileSync(cfg, "utf8");
      let data = null;
      try {
        const JSON5 = require("json5");
        data = JSON5.parse(raw);
      } catch (err) {
        try {
          data = JSON.parse(raw);
        } catch {
          data = null;
        }
      }
      const voiceId =
        (data && data.talk && data.talk.voiceId) ||
        (data && data.skills && data.skills.sag && data.skills.sag.voiceId) ||
        "";
      if (voiceId) process.stdout.write(String(voiceId));
    ' "$cfg" 2>/dev/null || true)"
    if [[ -n "$vid" ]]; then
      if [[ -n "$debug" ]]; then
        echo "debug: node config voiceId len=${#vid}" >&2
      fi
      printf '%s' "$vid"
      return 0
    fi
    if [[ -n "$debug" ]]; then
      echo "debug: node config voiceId len=0" >&2
    fi
  fi
  if command -v python3 >/dev/null 2>&1; then
    local py_vid
    py_vid="$(python3 - "$cfg" 2>/dev/null <<'PY' || true
import re
import sys
from pathlib import Path

cfg = Path(sys.argv[1])
if not cfg.exists():
    sys.exit(1)
text = cfg.read_text(encoding="utf-8", errors="ignore")

patterns = [
    r"talk\\s*:\\s*\\{[\\s\\S]*?voiceId\\s*:\\s*['\\\"]([^'\\\"]+)['\\\"]",
    r"skills\\s*:\\s*\\{[\\s\\S]*?sag\\s*:\\s*\\{[\\s\\S]*?voiceId\\s*:\\s*['\\\"]([^'\\\"]+)['\\\"]",
]
for pat in patterns:
    match = re.search(pat, text, re.IGNORECASE)
    if match:
        sys.stdout.write(match.group(1))
        sys.exit(0)
sys.exit(2)
PY
)"
    if [[ -n "$py_vid" ]]; then
      if [[ -n "$debug" ]]; then
        echo "debug: python config voiceId len=${#py_vid}" >&2
      fi
      printf '%s' "$py_vid"
      return 0
    fi
    if [[ -n "$debug" ]]; then
      echo "debug: python config voiceId len=0" >&2
    fi
  fi
  local line
  line="$(grep -m1 -E 'voiceId[[:space:]]*:' "$cfg" 2>/dev/null || true)"
  if [[ -n "$line" ]]; then
    local grep_voice
    grep_voice="$(printf '%s' "$line" | sed -E "s/.*voiceId[[:space:]]*:[[:space:]]*['\\\"]([^'\\\"]+)['\\\"].*/\\1/")"
    if [[ -n "$grep_voice" ]]; then
      if [[ -n "$debug" ]]; then
        echo "debug: grep config voiceId len=${#grep_voice}" >&2
      fi
      printf '%s' "$grep_voice"
      return 0
    fi
    if [[ -n "$debug" ]]; then
      echo "debug: grep config voiceId len=0" >&2
    fi
  fi
}

read_config_voice_alias() {
  local cfg="$1"
  local alias="${2:-}"
  if [[ -z "$alias" || ! -f "$cfg" ]]; then
    return 1
  fi
  if command -v node >/dev/null 2>&1; then
    local resolved
    resolved="$(node -e '
      const fs = require("fs");
      const cfg = process.argv[1];
      const alias = (process.argv[2] || "").toLowerCase();
      if (!fs.existsSync(cfg) || !alias) process.exit(1);
      const raw = fs.readFileSync(cfg, "utf8");
      let data = null;
      try {
        const JSON5 = require("json5");
        data = JSON5.parse(raw);
      } catch (err) {
        try {
          data = JSON.parse(raw);
        } catch {
          data = null;
        }
      }
      const aliases = (data && data.talk && data.talk.voiceAliases) || {};
      if (!aliases || typeof aliases !== "object") process.exit(2);
      const key = Object.keys(aliases).find((k) => k.toLowerCase() === alias);
      if (key && aliases[key]) process.stdout.write(String(aliases[key]));
    ' "$cfg" "$alias" 2>/dev/null || true)"
    if [[ -n "$resolved" ]]; then
      if [[ -n "$debug" ]]; then
        echo "debug: node config voice alias resolved len=${#resolved}" >&2
      fi
      printf '%s' "$resolved"
      return 0
    fi
    if [[ -n "$debug" ]]; then
      echo "debug: node config voice alias miss" >&2
    fi
  fi
  if command -v python3 >/dev/null 2>&1; then
    local py_resolved
    py_resolved="$(python3 - "$cfg" "$alias" 2>/dev/null <<'PY' || true
import re
import sys
from pathlib import Path

cfg = Path(sys.argv[1])
alias = (sys.argv[2] if len(sys.argv) > 2 else "").lower()
if not cfg.exists() or not alias:
    sys.exit(1)
text = cfg.read_text(encoding="utf-8", errors="ignore")
match = re.search(r"voiceAliases\\s*:\\s*\\{([\\s\\S]*?)\\}", text, re.IGNORECASE)
if not match:
    sys.exit(2)
block = match.group(1)
for item in re.finditer(r"([A-Za-z0-9_-]+)\\s*:\\s*['\\\"]([^'\\\"]+)['\\\"]", block):
    if item.group(1).lower() == alias:
        sys.stdout.write(item.group(2))
        sys.exit(0)
sys.exit(3)
PY
)"
    if [[ -n "$py_resolved" ]]; then
      if [[ -n "$debug" ]]; then
        echo "debug: python config voice alias resolved len=${#py_resolved}" >&2
      fi
      printf '%s' "$py_resolved"
      return 0
    fi
    if [[ -n "$debug" ]]; then
      echo "debug: python config voice alias miss" >&2
    fi
  fi
}

if [[ -n "$text_file" && ! -f "$text_file" ]]; then
  echo "Text file not found: $text_file" >&2
  exit 1
fi

if [[ -z "$out" ]]; then
  out="${tmpdir%/}/voice-reply.ogg"
fi

tmp_mp3=""
cleanup() {
  if [[ -n "$tmp_mp3" ]]; then
    rm -f "$tmp_mp3" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

if [[ -n "$text_file" ]]; then
  text="$(cat "$text_file")"
fi

if [[ -z "${text// }" ]]; then
  echo "Text is empty." >&2
  exit 1
fi

if ! [[ "$max_chars" =~ ^[0-9]+$ ]] || [[ "$max_chars" -le 0 ]]; then
  echo "Invalid --max-chars: $max_chars" >&2
  exit 1
fi

text_len=${#text}
if [[ "$text_len" -gt "$max_chars" ]]; then
  if [[ -n "$debug" ]]; then
    echo "debug: truncating text from $text_len to $max_chars chars" >&2
  fi
  text="${text:0:$max_chars}"
fi

tmp_mp3="$(mktemp -p "$tmpdir" voice-reply-XXXXXX.mp3)"

api_key="${ELEVENLABS_API_KEY:-}"
api_key="$(read_config_api_key "$config_path" || true)"
if [[ -n "$api_key" ]]; then
  api_key_source="config:${config_path}"
elif $allow_env; then
  api_key="${ELEVENLABS_API_KEY:-}"
  if [[ -z "$api_key" && -n "${SAG_API_KEY:-}" ]]; then
    api_key="$SAG_API_KEY"
    api_key_source="env:SAG_API_KEY"
  elif [[ -n "$api_key" ]]; then
    api_key_source="env:ELEVENLABS_API_KEY"
  fi
fi
if [[ -z "$api_key" ]]; then
  if [[ -n "$debug" ]]; then
    echo "debug: no api key found (config_path=${config_path})" >&2
  fi
  echo "Missing ElevenLabs API key (set talk.apiKey in ~/.openclaw/openclaw.json, or use --allow-env with ELEVENLABS_API_KEY/SAG_API_KEY)." >&2
  exit 1
fi
if [[ -n "$debug" ]]; then
  echo "debug: allow env=${allow_env}" >&2
  echo "debug: api key source=${api_key_source} len=${#api_key}" >&2
fi

if [[ -n "$voice" ]]; then
  voice_input="$voice"
  resolved_alias="$(read_config_voice_alias "$config_path" "$voice_input" || true)"
  if [[ -n "$resolved_alias" ]]; then
    voice="$resolved_alias"
    voice_source="config:talk.voiceAliases:${voice_input}"
  else
    voice_source="arg"
  fi
else
  voice="$(read_config_voice_id "$config_path" || true)"
  if [[ -n "$voice" ]]; then
    voice_source="config:talk.voiceId"
  elif $allow_env; then
    if [[ -n "${ELEVENLABS_VOICE_ID:-}" ]]; then
      voice="$ELEVENLABS_VOICE_ID"
      voice_source="env:ELEVENLABS_VOICE_ID"
    elif [[ -n "${SAG_VOICE_ID:-}" ]]; then
      voice="$SAG_VOICE_ID"
      voice_source="env:SAG_VOICE_ID"
    fi
  fi
fi
if [[ -n "$debug" ]]; then
  echo "debug: voice source=${voice_source:-none} value=${voice:-}" >&2
fi

if [[ -n "$voice" ]]; then
  sag --api-key "$api_key" -v "$voice" -o "$tmp_mp3" "$text"
else
  sag --api-key "$api_key" -o "$tmp_mp3" "$text"
fi

ffmpeg -y -hide_banner -loglevel error -i "$tmp_mp3" -c:a libopus -b:a "$bitrate" "$out"

if $emit_tag; then
  printf '[[audio_as_voice]]\nMEDIA:%s\n' "$out"
else
  printf '%s\n' "$out"
fi
