#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage:
  voice-note-active-tts.sh --text "hello" --out /tmp/reply.ogg [--emit-tag]
  voice-note-active-tts.sh --text-file /path/reply.txt --out /tmp/reply.ogg [--emit-tag]

Options:
  --text        Inline text to synthesize
  --text-file   Text file to synthesize
  --out         Output .ogg path (default: /tmp/reply-<ts>.ogg)
  --emit-tag    Print [[audio_as_voice]] + MEDIA:<out>
EOF
  exit 2
}

text=""
text_file=""
out=""
emit_tag=false

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
      shift
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
  [[ -f "$text_file" ]] || { echo "Missing text file: $text_file" >&2; exit 1; }
  text="$(cat "$text_file")"
fi

if [[ -z "${text//[[:space:]]/}" ]]; then
  echo "Input text is empty." >&2
  exit 1
fi

if [[ -z "$out" ]]; then
  out="/tmp/reply-$(date +%s).ogg"
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skills_root="$(cd "$script_dir/../.." && pwd)"
router_script="$skills_root/_common/tts-router.sh"
config_path="${OPENCLAW_CONFIG:-$HOME/.openclaw/openclaw.json}"
self_realpath="$(readlink -f "$0" 2>/dev/null || echo "$0")"

tmp_text_file="$(mktemp /tmp/openclaw-reply-text-XXXXXX.txt)"
cleanup() {
  rm -f "$tmp_text_file"
}
trap cleanup EXIT
printf '%s' "$text" >"$tmp_text_file"

read_timeout_seconds() {
  if [[ ! -f "$config_path" ]]; then
    echo "180"
    return 0
  fi
  if command -v jq >/dev/null 2>&1; then
    jq -r '.audio.reply.timeoutSeconds // 180' "$config_path" 2>/dev/null || echo "180"
    return 0
  fi
  python3 - "$config_path" <<'PY' 2>/dev/null || echo "180"
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as fh:
    cfg = json.load(fh)
timeout = cfg.get("audio", {}).get("reply", {}).get("timeoutSeconds", 180)
print(timeout)
PY
}

run_with_timeout() {
  local timeout_s="$1"
  shift
  if [[ "$timeout_s" =~ ^[0-9]+$ ]] && command -v timeout >/dev/null 2>&1; then
    timeout --signal=TERM "${timeout_s}s" "$@"
  else
    "$@"
  fi
}

load_reply_command() {
  local -n out_ref=$1
  out_ref=()

  [[ -f "$config_path" ]] || return 1

  if command -v jq >/dev/null 2>&1; then
    mapfile -t out_ref < <(jq -r '.audio.reply.command // empty | .[]?' "$config_path" 2>/dev/null)
  else
    mapfile -t out_ref < <(python3 - "$config_path" <<'PY' 2>/dev/null
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as fh:
    cfg = json.load(fh)
cmd = cfg.get("audio", {}).get("reply", {}).get("command", [])
if isinstance(cmd, list):
    for token in cmd:
        print(str(token))
PY
)
  fi

  [[ ${#out_ref[@]} -gt 0 ]]
}

run_active_reply_command() {
  local timeout_s="$1"
  local -a cmd_template=()
  local -a cmd=()
  local token=""
  local rendered=""
  local command_has_emit_tag=false

  load_reply_command cmd_template || return 1

  for token in "${cmd_template[@]}"; do
    rendered="$token"
    rendered="${rendered//\{\{ReplyTextFile\}\}/$tmp_text_file}"
    rendered="${rendered//\{\{ReplyAudioPath\}\}/$out}"
    if [[ "$rendered" == *"{{ReplyText}}"* ]]; then
      rendered="${rendered//\{\{ReplyText\}\}/$text}"
    fi
    cmd+=("$rendered")
    [[ "$rendered" == "--emit-tag" ]] && command_has_emit_tag=true
  done

  [[ ${#cmd[@]} -gt 0 ]] || return 1

  if [[ -f "${cmd[0]}" ]]; then
    local cmd0_realpath
    cmd0_realpath="$(readlink -f "${cmd[0]}" 2>/dev/null || echo "${cmd[0]}")"
    if [[ "$cmd0_realpath" == "$self_realpath" ]]; then
      echo "[voice-note-active-tts] Active reply command points to this wrapper; skipping recursive call." >&2
      return 1
    fi
  fi

  run_with_timeout "$timeout_s" "${cmd[@]}"
  [[ -s "$out" ]] || {
    echo "[voice-note-active-tts] Active reply command completed without output audio: $out" >&2
    return 1
  }

  if $emit_tag && ! $command_has_emit_tag; then
    echo "[[audio_as_voice]]"
    echo "MEDIA:$out"
  fi

  return 0
}

run_router_fallback() {
  [[ -x "$router_script" ]] || {
    echo "[voice-note-active-tts] Missing fallback router: $router_script" >&2
    return 1
  }

  local -a args=(--text-file "$tmp_text_file" --out "$out")
  $emit_tag && args+=(--emit-tag)
  "$router_script" "${args[@]}"
  [[ -s "$out" ]] || {
    echo "[voice-note-active-tts] Router fallback did not produce audio: $out" >&2
    return 1
  }
}

timeout_seconds="$(read_timeout_seconds)"
if run_active_reply_command "$timeout_seconds"; then
  exit 0
fi

echo "[voice-note-active-tts] Falling back to _common/tts-router.sh" >&2
run_router_fallback
