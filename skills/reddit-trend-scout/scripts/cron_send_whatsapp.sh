#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:-+919845402211}"
PYTHON_BIN="${PYTHON_BIN:-/home/linuxbrew/.linuxbrew/bin/python3}"
SKILL_SCRIPT="/home/shkas/projects/raaz/skills/reddit-trend-scout/scripts/reddit_trend_scout.py"
REDDIT_CLI_SCRIPT="/home/shkas/projects/raaz/skills/reddit-cli/scripts/reddit_cli.py"
SUBREDDITS="wallstreetbets,stocks,investing,StockMarket,options,ValueInvesting,IndianStockMarket,IndiaInvestments,DalalStreetTalks,Commodities,energy,gold,Silverbugs"
MAX_ATTEMPTS="${REDDIT_TREND_SCOUT_MAX_ATTEMPTS:-3}"
RETRY_BASE_SECONDS="${REDDIT_TREND_SCOUT_RETRY_BASE_SECONDS:-5}"
PREFLIGHT_TIMEOUT_SECONDS="${REDDIT_TREND_SCOUT_PREFLIGHT_TIMEOUT_SECONDS:-45}"

AUTH_ARGS=(--auth auto)

TMP_REPORT="$(mktemp /tmp/reddit-trend-scout-report.XXXXXX.md)"
TMP_ERR="$(mktemp /tmp/reddit-trend-scout-err.XXXXXX.log)"

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
    TRANSIENT_MSG="Reddit trend preflight failed (source blocked/rate-limited). This run was skipped and will retry on the next schedule."
    openclaw message send --channel whatsapp --target "$TARGET" --message "$TRANSIENT_MSG" --json >/dev/null 2>&1 || true
    echo "SENT_TRANSIENT_NOTICE_PREFLIGHT"
    exit 0
  fi
  openclaw message send --channel whatsapp --target "$TARGET" --message "Reddit trend scout preflight failed." --json >/dev/null 2>&1 || true
  printf 'ERROR: reddit_trend_scout preflight failed\n' >&2
  cat "$TMP_ERR" >&2 || true
  exit 1
fi

run_ok=false
attempt=1
while (( attempt <= MAX_ATTEMPTS )); do
  : >"$TMP_ERR"
  if timeout 180 "$PYTHON_BIN" "$SKILL_SCRIPT" \
    "${AUTH_ARGS[@]}" \
    --scope custom \
    --subreddits "$SUBREDDITS" \
    --sort rising \
    --post-limit 40 \
    --trend-limit 15 \
    --max-age-hours 48 \
    --max-retries 6 \
    --format md >"$TMP_REPORT" 2>"$TMP_ERR"; then
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
    TRANSIENT_MSG="Reddit trend scan is temporarily blocked/rate-limited. I will retry automatically on the next scheduled run."
    openclaw message send --channel whatsapp --target "$TARGET" --message "$TRANSIENT_MSG" --json >/dev/null 2>&1 || true
    echo "SENT_TRANSIENT_NOTICE"
    exit 0
  fi
  openclaw message send --channel whatsapp --target "$TARGET" --message "Reddit trend scout error." --json >/dev/null 2>&1 || true
  printf 'ERROR: reddit_trend_scout command failed\n' >&2
  cat "$TMP_ERR" >&2 || true
  exit 1
fi

REPORT_TEXT="$(cat "$TMP_REPORT")"
if [[ -z "${REPORT_TEXT//[[:space:]]/}" ]]; then
  REPORT_TEXT="No qualifying Reddit trends today."
elif grep -qi "No trends matched" "$TMP_REPORT"; then
  if grep -qi "Fetch warnings:" "$TMP_REPORT"; then
    REPORT_TEXT="Reddit trend scan is source-degraded (subreddit fetch failures such as HTTP 403/429). No trend candidates were available in this run. Configure OAuth credentials for stable coverage."
  else
    REPORT_TEXT="No qualifying Reddit trends today."
  fi
fi

if openclaw message send --channel whatsapp --target "$TARGET" --message "$REPORT_TEXT" --json >/dev/null 2>&1; then
  echo "SENT_TEXT"
  exit 0
fi

FALLBACK_FILE="/tmp/reddit-trend-scout-$(date +%Y%m%d-%H%M%S).md"
printf '%s\n' "$REPORT_TEXT" >"$FALLBACK_FILE"
openclaw message send --channel whatsapp --target "$TARGET" --media "$FALLBACK_FILE" --message "Reddit trend scout report attached." --json >/dev/null

echo "SENT_MEDIA $FALLBACK_FILE"
