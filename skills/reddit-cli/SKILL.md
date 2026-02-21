---
name: reddit-cli
description: Dedicated Reddit CLI for production-grade listing fetches with OAuth-aware auth selection, retries, and structured JSON output.
---

# Reddit CLI

Single source of truth for Reddit fetch/auth behavior used by Raaz Reddit skills.

## Quick Start

Check connectivity and active auth mode:

```bash
python {baseDir}/scripts/reddit_cli.py check --auth auto
```

Fetch subreddit posts:

```bash
python {baseDir}/scripts/reddit_cli.py posts \
  --subreddit IndianStockMarket \
  --sort new \
  --limit 50 \
  --auth auto
```

Fetch subreddit directory listings:

```bash
python {baseDir}/scripts/reddit_cli.py subreddits \
  --where popular \
  --limit 25 \
  --auth auto
```

## Auth Modes

- `auto` (recommended): use OAuth if credentials exist, else public mode.
- `public`: no OAuth token.
- `app`: OAuth client credentials.
- `refresh`: OAuth refresh token flow.

Environment variables supported:

- `REDDIT_CLIENT_ID`
- `REDDIT_CLIENT_SECRET`
- `REDDIT_REFRESH_TOKEN`
- `REDDIT_USER_AGENT`

## Notes

- Output is deterministic JSON suitable for downstream scripts/jobs.
- This CLI is the canonical Reddit fetch implementation for trend and sentiment skills.
