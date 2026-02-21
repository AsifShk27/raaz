# Change: Reddit CLI Shared Core Rollout and Skill Dedup Refactor

Date: 2026-02-21
Type: Reliability + architecture cleanup

## What changed

- Added new dedicated skill:
  - `skills/reddit-cli/SKILL.md`
  - `skills/reddit-cli/lib/reddit_api.py`
  - `skills/reddit-cli/scripts/reddit_cli.py`
  - `skills/reddit-cli/tests/test_reddit_api.py`
- Replaced duplicated sentiment Reddit stack:
  - `skills/reddit-market-sentiment/scripts/rms_reddit.py` now imports shared core.
- Replaced duplicated trend Reddit stack:
  - `skills/reddit-trend-scout/scripts/reddit_trend_scout.py` now imports shared core.
  - Removed duplicated `HttpClient`, `RedditAuth`, `RedditClient`, and listing fetch functions.
- Added `skills/reddit-trend-scout/scripts/trend_render.py` and split rendering logic to keep main script file under 500 lines.
- Updated skill docs:
  - `skills/reddit-market-sentiment/SKILL.md`
  - `skills/reddit-trend-scout/SKILL.md`
- Changed auth defaults:
  - sentiment and trend now default to `--auth auto`.

## Why

- Enforce single source of truth for Reddit integration.
- Remove redundant/bespoke implementations and drift risk.
- Improve production reliability under Reddit public endpoint variability.

## Validation evidence

- Syntax checks:
  - `python3 -m py_compile` passed for all changed scripts/modules.
- Live runtime checks:
  - `reddit_cli.py check` and `reddit_cli.py posts` returned valid JSON.
  - sentiment run returned expected markdown with symbol table/top links.
  - trend run returned ranked trends with links and metrics.

## Rollback / risk notes

- Rollback is localized: restore previous `rms_reddit.py` and in-file trend HTTP/auth classes.
- Runtime dependency risk: `requests` should remain available for best reliability; fallback remains in place.
