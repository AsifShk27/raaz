#!/usr/bin/env bash
set -euo pipefail

PROVIDER="${COLLAB_USAGE_PROVIDER:-codex}"
SOURCE="${COLLAB_USAGE_SOURCE:-cli}"
OUT_PATH="${COLLAB_USAGE_PATH:-}"

if [[ -z "$OUT_PATH" ]]; then
  if [[ -n "${AGENT_COLLAB_ROOT:-}" ]]; then
    OUT_PATH="${AGENT_COLLAB_ROOT}/usage/codexbar-usage.json"
  else
    OUT_PATH="${HOME}/.openclaw/codexbar-usage.json"
  fi
fi

if ! command -v codexbar >/dev/null 2>&1; then
  export PATH="/home/linuxbrew/.linuxbrew/bin:$PATH"
fi

if ! command -v codexbar >/dev/null 2>&1; then
  echo "codexbar not found on PATH." >&2
  exit 1
fi

tmp_file="$(mktemp)"
cleanup() { rm -f "$tmp_file"; }
trap cleanup EXIT

if ! codexbar usage --provider "$PROVIDER" --format json --pretty --source "$SOURCE" >"$tmp_file" 2>/dev/null; then
  if [[ "$SOURCE" != "cli" ]]; then
    SOURCE="cli"
    codexbar usage --provider "$PROVIDER" --format json --pretty --source "$SOURCE" >"$tmp_file"
  else
    echo "codexbar usage failed." >&2
    exit 1
  fi
fi

mkdir -p "$(dirname "$OUT_PATH")"
mv "$tmp_file" "$OUT_PATH"

echo "Wrote usage snapshot to: $OUT_PATH (source=$SOURCE)"
