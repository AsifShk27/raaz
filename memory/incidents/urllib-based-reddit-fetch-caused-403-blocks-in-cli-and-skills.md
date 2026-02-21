# Incident: urllib-Based Reddit Fetch Caused 403 Blocks in CLI and Skills

Date: 2026-02-21
Status: Resolved
Severity: Medium (data-source degradation risk)

## Summary

- New dedicated Reddit CLI initially used `urllib` transport.
- In this runtime, `urllib` requests to Reddit JSON endpoints returned `HTTP 403 Blocked`.
- Equivalent `requests` client calls with the same user-agent/accept behavior succeeded.

## Impact

- Dedicated CLI health/post fetch failed in public mode despite endpoint availability.
- This could propagate false "all fetches failed" behavior in sentiment/trend jobs.

## Root cause

- Transport/client fingerprint differences from `urllib` triggered Reddit blocking in this environment.
- Retry logic alone could not recover because failures were deterministic `403` responses.

## Fix

- Updated shared core `skills/reddit-cli/lib/reddit_api.py` to:
  - use `requests` transport when available,
  - keep `urllib` fallback for minimal environments,
  - preserve existing retry/error contracts.

## Validation evidence

- Failing path reproduced pre-fix:
  - `python3 skills/reddit-cli/scripts/reddit_cli.py check --auth public` returned `HTTP 403`.
- Post-fix successful:
  - `python3 skills/reddit-cli/scripts/reddit_cli.py check --auth public --format pretty`
  - `python3 skills/reddit-cli/scripts/reddit_cli.py posts --subreddit IndianStockMarket --sort new --limit 2 --auth public --format pretty`

## Prevention / follow-up

- Keep transport logic centralized in `reddit_api.py`.
- Preserve OAuth-first (`--auth auto`) for production schedules to reduce public-endpoint fragility.
