# Change: Reddit Cron Preflight Gate via Shared Reddit CLI Check

Date: 2026-02-21
Type: Runtime hardening

## What changed

- Added a hard preflight check in both Reddit cron wrappers before running main scans:
  - `skills/reddit-market-sentiment/scripts/cron_send_whatsapp.sh`
  - `skills/reddit-trend-scout/scripts/cron_send_whatsapp.sh`
- Preflight uses:
  - `python3 skills/reddit-cli/scripts/reddit_cli.py check --auth auto --format json`
- Both wrappers now default to `AUTH_ARGS=(--auth auto)` and no longer implement separate app/public auth selection logic.
- Added transient-vs-fatal preflight handling:
  - transient (403/429/timeout) sends a skip/retry notice and exits success,
  - non-transient preflight failures send explicit failure notice and exit non-zero.

## Why

- Prevent expensive scan runs when Reddit source access is unavailable.
- Ensure both cron jobs gate through the single-source shared Reddit CLI and auth behavior.
- Improve operator clarity by reporting preflight failures separately from scan execution failures.

## Validation evidence

- Syntax checks passed:
  - `bash -n .../reddit-market-sentiment/scripts/cron_send_whatsapp.sh`
  - `bash -n .../reddit-trend-scout/scripts/cron_send_whatsapp.sh`
- Preflight command path verified:
  - `reddit_cli.py check --auth auto --format json` returned success with JSON payload.

## Rollback / risk notes

- Rollback path: remove `run_preflight_check` block and restore prior wrappers.
- Operational risk: preflight introduces an additional dependency on `skills/reddit-cli/scripts/reddit_cli.py`; wrapper now fails fast if that path is broken.
