---
name: reddit-market-sentiment
description: Analyze Reddit sentiment for US/India equities and commodities (oil, gas, gold, silver, metals) by scanning market subreddits, matching asset keywords, and scoring post sentiment. Use when asked for Reddit-based market sentiment, daily sentiment digests, or to set up scheduled sentiment scans.
---

# Reddit Market Sentiment

## Overview
Generate Reddit-based sentiment snapshots for US equities, Indian equities, and commodities using a deterministic keyword + lexicon pipeline. Outputs markdown and JSON summaries suitable for daily cron delivery or on-demand analysis.
This skill uses the centralized `reddit-cli` fetch core for Reddit auth/retry behavior.

## Quick Start

Run a full scan with defaults (US + India + commodities):
```bash
python {baseDir}/scripts/reddit_market_sentiment.py --format md
```

Write both JSON + markdown to a file prefix:
```bash
python {baseDir}/scripts/reddit_market_sentiment.py \
  --format both --out /tmp/reddit-market-sentiment
```

Limit to a group:
```bash
python {baseDir}/scripts/reddit_market_sentiment.py \
  --groups us,india --format md
```

## Cron / Daily Guard

Use `--once-per-day` to enforce a single run per IST day. The marker file defaults to
`/home/shkas/projects/raaz/memory/reddit-market-sentiment-last.txt`.

```bash
python {baseDir}/scripts/reddit_market_sentiment.py \
  --once-per-day --format md
```

If running in cron, do NOT ask for recipients. Cron routing handles delivery.

## Optional Summaries (summarize CLI)

You can enrich top posts using the `summarize` CLI (requires API key).
Enable via `--summarize-top <N>` or set defaults in `references/market-sentiment-config.json`.

```bash
python {baseDir}/scripts/reddit_market_sentiment.py \
  --summarize-top 6 --summarize-length short --summarize-max-output-tokens 160 \
  --summarize-model cli/codex/gpt-5.2
```

Summarize CLI keys:
- `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `XAI_API_KEY`, or `GEMINI_API_KEY`
  - For Codex CLI, ensure the `codex` CLI is installed and authenticated.

## Configuration

Edit the default config to change subreddits or assets:
- `references/market-sentiment-config.json`

Override config path:
```bash
python {baseDir}/scripts/reddit_market_sentiment.py \
  --config /path/to/custom-config.json
```

## OAuth (Optional)

Public endpoints work without credentials, but OAuth is more reliable at higher volumes.
Default mode is `--auth auto` (uses OAuth when credentials are present).

```bash
export REDDIT_CLIENT_ID="..."
export REDDIT_CLIENT_SECRET="..."
export REDDIT_REFRESH_TOKEN="..."
python {baseDir}/scripts/reddit_market_sentiment.py --auth app
```

## Output

Markdown report includes:
- Per-group sentiment table (US / India / commodities)
- Aggregate sentiment + volume metrics
- Top posts per group with links
- Explicit fallback annotation when strict filters return no matches for a requested group

JSON report includes:
- Per-asset metrics, sentiment scores, and top mentions
- Full metadata and filter settings for reproducibility

## Notes

- This is a multi-factor heuristic model (keyword + context + recency + engagement). Treat as directional signal only.
- Keep `--post-limit` modest to avoid rate limits.
- For hourly jobs, tune freshness weighting with `--recency-half-life-hours` (default: `18`).
- Use OAuth for larger scans.
