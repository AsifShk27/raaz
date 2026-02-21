---
name: reddit-trend-scout-now
description: On-demand Reddit trend scan with monetization angles (no schedule, run anytime).
metadata: {"openclaw":{"emoji":"🧭","requires":{"anyBins":["python3","python"]}}}
---

# reddit-trend-scout-now

Run a **Reddit trend scan on-demand**. This is the manual, anytime version of the daily cron job.

## What it does
- Scans fast-rising posts
- Ranks by momentum (score/hour + comments/hour)
- Extracts buyer intent and pain points
- Outputs direct Reddit links + monetization angles

## Run (recommended)

```bash
python {baseDir}/../reddit-trend-scout/scripts/reddit_trend_scout.py \
  --scope popular --sort rising --post-limit 40 --trend-limit 15 \
  --max-age-hours 48 --format md
```

## Options
- `--scope popular|all|custom`
- `--subreddits "A,B,C"` or `--subreddits-file ./subs.txt`
- `--sort hot|new|rising|top` (+ `--time day|week|month|year|all` for `top`)
- `--format md|json|both`

## Notes
- Always follow subreddit rules and Reddit API policies.
- This on-demand run does **not** update any daily marker files.
