#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:-+919845402211}"
PYTHON_BIN="${PYTHON_BIN:-/home/linuxbrew/.linuxbrew/bin/python3}"
SKILL_SCRIPT="/home/shkas/projects/raaz/skills/reddit-market-sentiment/scripts/reddit_market_sentiment.py"
REDDIT_CLI_SCRIPT="/home/shkas/projects/raaz/skills/reddit-cli/scripts/reddit_cli.py"
MAX_ATTEMPTS="${REDDIT_MARKET_SENTIMENT_MAX_ATTEMPTS:-3}"
RETRY_BASE_SECONDS="${REDDIT_MARKET_SENTIMENT_RETRY_BASE_SECONDS:-5}"
PREFLIGHT_TIMEOUT_SECONDS="${REDDIT_MARKET_SENTIMENT_PREFLIGHT_TIMEOUT_SECONDS:-45}"

AUTH_ARGS=(--auth auto)

TMP_REPORT="$(mktemp /tmp/reddit-market-sentiment-report.XXXXXX.md)"
TMP_ERR="$(mktemp /tmp/reddit-market-sentiment-err.XXXXXX.log)"

cleanup() {
  rm -f "$TMP_REPORT" "$TMP_ERR"
}
trap cleanup EXIT

is_transient_error() {
  local file="$1"
  grep -Eqi "HTTP Error 403: Blocked|HTTP 403|HTTP 429|Failed request after|timed out" "$file"
}

run_preflight_check() {
  : >"$TMP_ERR"
  timeout "$PREFLIGHT_TIMEOUT_SECONDS" "$PYTHON_BIN" "$REDDIT_CLI_SCRIPT" check \
    "${AUTH_ARGS[@]}" \
    --format json > /dev/null 2>"$TMP_ERR"
}

if ! run_preflight_check; then
  if is_transient_error "$TMP_ERR"; then
    TRANSIENT_MSG="Reddit market sentiment preflight failed (source blocked/rate-limited). This run was skipped and will retry on the next schedule."
    openclaw message send --channel whatsapp --target "$TARGET" --message "$TRANSIENT_MSG" --json >/dev/null 2>&1 || true
    echo "SENT_TRANSIENT_NOTICE_PREFLIGHT"
    exit 0
  fi
  openclaw message send --channel whatsapp --target "$TARGET" --message "Reddit market sentiment preflight failed." --json >/dev/null 2>&1 || true
  printf 'ERROR: reddit_market_sentiment preflight failed\n' >&2
  cat "$TMP_ERR" >&2 || true
  exit 1
fi

run_ok=false
attempt=1
while (( attempt <= MAX_ATTEMPTS )); do
  : >"$TMP_ERR"
  if timeout 180 "$PYTHON_BIN" "$SKILL_SCRIPT" \
    "${AUTH_ARGS[@]}" \
    --format md \
    --summarize-top 0 \
    --max-retries 6 >"$TMP_REPORT" 2>"$TMP_ERR"; then
    run_ok=true
    break
  fi

  if (( attempt < MAX_ATTEMPTS )) && is_transient_error "$TMP_ERR"; then
    sleep_for=$((RETRY_BASE_SECONDS * attempt))
    sleep "$sleep_for"
    attempt=$((attempt + 1))
    continue
  fi
  break
done

if [[ "$run_ok" != "true" ]]; then
  if is_transient_error "$TMP_ERR"; then
    TRANSIENT_MSG="Reddit market sentiment scan is temporarily blocked/rate-limited. I will retry automatically on the next scheduled run."
    openclaw message send --channel whatsapp --target "$TARGET" --message "$TRANSIENT_MSG" --json >/dev/null 2>&1 || true
    echo "SENT_TRANSIENT_NOTICE"
    exit 0
  fi
  openclaw message send --channel whatsapp --target "$TARGET" --message "Reddit market sentiment error." --json >/dev/null 2>&1 || true
  printf 'ERROR: reddit_market_sentiment command failed\n' >&2
  cat "$TMP_ERR" >&2 || true
  exit 1
fi

REPORT_TEXT="$(cat "$TMP_REPORT")"
if [[ -z "${REPORT_TEXT//[[:space:]]/}" ]] || grep -qi "No sentiment matches found" "$TMP_REPORT"; then
  REPORT_TEXT="No qualifying Reddit sentiment signals today."
fi

if openclaw message send --channel whatsapp --target "$TARGET" --message "$REPORT_TEXT" --json >/dev/null 2>&1; then
  echo "SENT_TEXT"
  exit 0
fi

FALLBACK_FILE="/tmp/reddit-market-sentiment-$(date +%Y%m%d-%H%M%S).md"
printf '%s\n' "$REPORT_TEXT" >"$FALLBACK_FILE"
openclaw message send --channel whatsapp --target "$TARGET" --media "$FALLBACK_FILE" --message "Reddit market sentiment report attached." --json >/dev/null

echo "SENT_MEDIA $FALLBACK_FILE"
