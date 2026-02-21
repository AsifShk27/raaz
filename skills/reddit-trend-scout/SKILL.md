---
name: reddit-trend-scout
description: Scan Reddit for fast-rising posts and generate monetization angles with direct post links.
homepage: https://www.reddit.com/dev/api/
metadata: {"openclaw":{"requires":{"anyBins":["python3","python"]}}}
---

# Reddit Trend Scout

Find fast-rising Reddit posts, rank them by momentum, and suggest monetization angles. Output includes direct post links and optional JSON for downstream LLM analysis.

This skill uses the centralized `reddit-cli` fetch core for Reddit auth/retry behavior.

## Quick start

```bash
python {baseDir}/scripts/reddit_trend_scout.py --scope popular --sort rising --post-limit 40 --trend-limit 15 --format both --out ./tmp/reddit-trends
```

### Custom subreddits

```bash
python {baseDir}/scripts/reddit_trend_scout.py --scope custom --subreddits "Entrepreneur,SideProject,IndieHackers" --sort hot --trend-limit 20 --format md
```

Or use a file with one subreddit per line:

```bash
python {baseDir}/scripts/reddit_trend_scout.py --scope custom --subreddits-file ./subreddits.txt --sort hot --trend-limit 20 --format json --out ./tmp/reddit-trends.json
```

### Auto-discover subreddits

```bash
python {baseDir}/scripts/reddit_trend_scout.py --discover-subreddits popular --subreddit-limit 25 --sort rising --post-limit 30
```

## Output

- Markdown report (default) with direct links to each post and subreddit
- JSON payload for downstream analysis (`--format json` or `--format both`)

## OAuth (optional)

Public endpoints work without credentials, but OAuth is more reliable for higher volumes.
Default mode is `--auth auto` (uses OAuth when credentials are present).

```bash
export REDDIT_CLIENT_ID="..."
export REDDIT_CLIENT_SECRET="..."
export REDDIT_REFRESH_TOKEN="..."  # only if using --auth refresh
python {baseDir}/scripts/reddit_trend_scout.py --auth app --scope all --sort hot
```

## Key flags

- `--scope popular|all|custom`
- `--discover-subreddits popular|new`
- `--sort hot|new|rising|top` (+ `--time day|week|month|year|all` when `--sort top`)
- `--post-limit <n>` (per subreddit)
- `--trend-limit <n>` (final ranked output)
- `--max-age-hours <hours>` (drop stale posts)
- `--min-score`, `--min-comments`, `--min-upvote-ratio`
- `--format md|json|both`
- `--out <path>` (file or prefix when using `--format both`)

## Notes

- Always follow subreddit rules and Reddit API policies. Avoid spammy outreach; validate demand with opt-in surveys or landing pages.
- For large scans, prefer OAuth and conservative limits.

## References

- Local notes: `{baseDir}/references/reddit-api.md`
- Reddit API listings: https://www.reddit.com/dev/api/
- OAuth details: https://github.com/reddit-archive/reddit/wiki/OAuth2
