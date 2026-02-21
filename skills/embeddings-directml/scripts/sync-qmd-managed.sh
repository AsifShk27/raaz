#!/usr/bin/env bash
set -euo pipefail

SRC_QMD_ROOT="${SRC_QMD_ROOT:-/home/shkas/.npm-global/lib/node_modules/qmd}"
DST_QMD_ROOT="${DST_QMD_ROOT:-/home/shkas/projects/raaz/.runtime/qmd-managed}"

if [[ ! -f "$SRC_QMD_ROOT/src/qmd.ts" ]]; then
  echo "[sync-qmd-managed] source qmd not found at $SRC_QMD_ROOT" >&2
  exit 1
fi

mkdir -p "$DST_QMD_ROOT"
rsync -a --delete "$SRC_QMD_ROOT/" "$DST_QMD_ROOT/"

if ! rg -q "QMD_EMBEDDINGS_PROVIDER" "$DST_QMD_ROOT/src/llm.ts"; then
  echo "[sync-qmd-managed] ERROR: synced qmd does not contain OpenAI embeddings patch marker." >&2
  echo "[sync-qmd-managed] Refusing to keep unmanaged/unpatched qmd in production path." >&2
  exit 2
fi

echo "[sync-qmd-managed] Synced managed runtime: $DST_QMD_ROOT"
