# Decision: Reddit Skills Must Use Shared Reddit CLI Core and Auto OAuth

Date: 2026-02-21
Status: Accepted
Scope: Raaz Reddit skills (`reddit-market-sentiment`, `reddit-trend-scout`, `reddit-cli`)

## What changed

- Adopted a single shared Reddit fetch/auth implementation in:
  - `skills/reddit-cli/lib/reddit_api.py`
- Both Reddit skills now import this shared core instead of maintaining duplicate HTTP/auth stacks.
- Default auth mode moved to `auto` for both skills:
  - Uses OAuth when `REDDIT_CLIENT_ID` + `REDDIT_CLIENT_SECRET` exist.
  - Falls back to public mode when credentials are missing.

## Why

- Duplicate fetch stacks caused drift and confusion across sentiment and trend behavior.
- Public-only mode was fragile under Reddit anti-bot behavior and credential availability changes.
- A single source of truth is required for predictable reliability and maintenance.

## Validation evidence

- `python3 -m py_compile` passed for:
  - `skills/reddit-cli/lib/reddit_api.py`
  - `skills/reddit-cli/scripts/reddit_cli.py`
  - `skills/reddit-market-sentiment/scripts/reddit_market_sentiment.py`
  - `skills/reddit-market-sentiment/scripts/rms_reddit.py`
  - `skills/reddit-trend-scout/scripts/reddit_trend_scout.py`
  - `skills/reddit-trend-scout/scripts/trend_render.py`
- Live smoke checks succeeded:
  - `python3 skills/reddit-cli/scripts/reddit_cli.py check --auth public --format pretty`
  - `python3 skills/reddit-cli/scripts/reddit_cli.py posts --subreddit IndianStockMarket --sort new --limit 2 --auth public --format pretty`
  - sentiment and trend scripts returned valid markdown output with `--auth auto`.

## Rollback / risk notes

- Rollback path: revert skill imports back to local implementations in each skill.
- Risk: if `requests` is unavailable in a runtime, shared core falls back to `urllib`; behavior may be less reliable against Reddit anti-bot controls.
