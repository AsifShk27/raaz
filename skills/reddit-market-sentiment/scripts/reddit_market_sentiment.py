#!/usr/bin/env python3
"""Reddit Market Sentiment: scan market subreddits and score asset sentiment."""

from __future__ import annotations

import argparse
import dataclasses
import datetime as dt
import json
import os
import time
from pathlib import Path
from typing import Optional, Sequence

from rms_config import (
    DEFAULT_MARKER,
    build_assets,
    build_subreddits,
    load_config,
    resolve_timezone,
    should_run_today,
    write_marker,
)
from rms_models import PostMatch
from rms_reddit import DEFAULT_USER_AGENT, HttpClient, RedditAuth, RedditClient, fetch_posts
from rms_render import render_markdown
from rms_sentiment import build_asset_sentiment, filter_posts
from rms_summarize import summarize_urls


def _requested_groups(assets: Sequence) -> list[str]:
    return sorted({str(asset.group) for asset in assets if str(getattr(asset, "group", "")).strip()})


def _apply_missing_group_fallback(
    *,
    assets: Sequence,
    all_posts: Sequence[dict],
    strict_sentiment: dict,
    now_ts: float,
    max_age_hours: float,
    recency_half_life_hours: float,
    include_nsfw: bool,
) -> tuple[dict, dict]:
    requested_groups = _requested_groups(assets)
    missing_groups = [group for group in requested_groups if not strict_sentiment.get(group)]
    fallback_meta = {
        "applied": False,
        "requested_missing_groups": missing_groups,
        "covered_groups": [],
        "relaxed_filters": {
            "min_score": 0,
            "min_comments": 0,
            "min_upvote_ratio": 0.0,
        },
    }

    if not missing_groups:
        return strict_sentiment, fallback_meta

    relaxed_posts = filter_posts(
        all_posts,
        now_ts=now_ts,
        max_age_hours=max_age_hours,
        min_score=0,
        min_comments=0,
        min_ratio=0.0,
        include_nsfw=include_nsfw,
    )
    if not relaxed_posts:
        return strict_sentiment, fallback_meta

    relaxed_assets = [asset for asset in assets if asset.group in missing_groups]
    if not relaxed_assets:
        return strict_sentiment, fallback_meta

    relaxed_sentiment = build_asset_sentiment(
        relaxed_assets,
        relaxed_posts,
        now_ts=now_ts,
        recency_half_life_hours=recency_half_life_hours,
    )

    covered_groups: list[str] = []
    for group in missing_groups:
        group_assets = relaxed_sentiment.get(group, [])
        if not group_assets:
            continue
        strict_sentiment[group] = group_assets
        covered_groups.append(group)

    fallback_meta["covered_groups"] = covered_groups
    fallback_meta["applied"] = bool(covered_groups)
    return strict_sentiment, fallback_meta


def parse_args(argv: Optional[Sequence[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Scan Reddit for market sentiment.")
    parser.add_argument(
        "--config",
        default=str(Path(__file__).parent.parent / "references/market-sentiment-config.json"),
    )
    parser.add_argument("--groups", help="Comma-separated group keys (us,india,commodities)")
    parser.add_argument("--format", choices=["md", "json", "both"], default="md")
    parser.add_argument("--out", help="Output file path (or prefix when using --format both)")
    parser.add_argument("--sort", choices=["hot", "new", "rising", "top"])
    parser.add_argument("--time", dest="time_filter")
    parser.add_argument("--post-limit", type=int)
    parser.add_argument("--max-age-hours", type=float)
    parser.add_argument("--recency-half-life-hours", type=float)
    parser.add_argument("--min-score", type=int)
    parser.add_argument("--min-comments", type=int)
    parser.add_argument("--min-upvote-ratio", type=float)
    parser.add_argument("--include-nsfw", action="store_true")
    parser.add_argument("--auth", choices=["auto", "public", "app", "refresh"], default="auto")
    parser.add_argument("--client-id", default=os.environ.get("REDDIT_CLIENT_ID"))
    parser.add_argument("--client-secret", default=os.environ.get("REDDIT_CLIENT_SECRET"))
    parser.add_argument("--refresh-token", default=os.environ.get("REDDIT_REFRESH_TOKEN"))
    parser.add_argument("--user-agent", default=DEFAULT_USER_AGENT)
    parser.add_argument("--timeout", type=int, default=30)
    parser.add_argument("--max-retries", type=int, default=4)
    parser.add_argument("--sleep-ms", type=int, default=250)
    parser.add_argument("--strict-fetch", action="store_true")
    parser.add_argument("--summarize-top", type=int, default=0)
    parser.add_argument("--summarize-model")
    parser.add_argument("--summarize-length")
    parser.add_argument("--summarize-max-output-tokens", type=int)
    parser.add_argument("--summarize-firecrawl")
    parser.add_argument("--once-per-day", action="store_true")
    parser.add_argument("--marker-file", default=DEFAULT_MARKER)
    parser.add_argument("--timezone")
    return parser.parse_args(argv)


def resolve_base_path(out_path: Optional[str]) -> Path:
    if out_path:
        path = Path(out_path)
        if path.suffix:
            return path.with_suffix("")
        return path
    timestamp = dt.datetime.utcnow().strftime("%Y%m%d-%H%M%S")
    return Path.cwd() / f"reddit-market-sentiment-{timestamp}"


def main(argv: Optional[Sequence[str]] = None) -> int:
    args = parse_args(argv)
    config_path = Path(args.config)
    config = load_config(config_path)

    defaults = config.get("defaults", {})
    timezone = args.timezone or defaults.get("timezone", "Asia/Kolkata")
    tz = resolve_timezone(timezone)
    marker_path = Path(args.marker_file)
    if args.once_per_day:
        if not should_run_today(marker_path, tz):
            return 0

    group_list = [g.strip() for g in args.groups.split(",")] if args.groups else None
    assets = build_assets(config, group_list)
    if not assets:
        raise SystemExit("No assets configured for the requested groups.")
    subreddits = build_subreddits(config, group_list)

    sort = args.sort or defaults.get("sort", "new")
    time_filter = args.time_filter or defaults.get("time_filter", "day")
    post_limit = args.post_limit if args.post_limit is not None else int(defaults.get("post_limit", 80))
    max_age_hours = args.max_age_hours if args.max_age_hours is not None else float(defaults.get("max_age_hours", 72))
    recency_half_life_hours = (
        args.recency_half_life_hours
        if args.recency_half_life_hours is not None
        else float(defaults.get("recency_half_life_hours", 18))
    )
    min_score = args.min_score if args.min_score is not None else int(defaults.get("min_score", 5))
    min_comments = args.min_comments if args.min_comments is not None else int(defaults.get("min_comments", 2))
    min_ratio = (
        args.min_upvote_ratio
        if args.min_upvote_ratio is not None
        else float(defaults.get("min_upvote_ratio", 0.6))
    )
    summarize_config = defaults.get("summarize", {})
    summarize_top = args.summarize_top if args.summarize_top is not None else int(summarize_config.get("top", 0))
    summarize_length = args.summarize_length or summarize_config.get("length")
    summarize_model = args.summarize_model or summarize_config.get("model")
    summarize_max_tokens = (
        args.summarize_max_output_tokens
        if args.summarize_max_output_tokens is not None
        else summarize_config.get("max_output_tokens")
    )
    summarize_firecrawl = args.summarize_firecrawl or summarize_config.get("firecrawl")

    http = HttpClient(
        user_agent=args.user_agent,
        timeout=args.timeout,
        max_retries=args.max_retries,
        sleep_ms=args.sleep_ms,
    )
    auth = RedditAuth(
        http=http,
        auth_mode=args.auth,
        client_id=args.client_id,
        client_secret=args.client_secret,
        refresh_token=args.refresh_token,
    )
    client = RedditClient(http=http, auth=auth)

    now_ts = time.time()
    all_posts: list[dict] = []
    seen: set[str] = set()
    fetch_errors: list[str] = []
    for sub in subreddits:
        try:
            posts = fetch_posts(client, sub, sort, time_filter, post_limit)
        except Exception as exc:
            warning = f"r/{sub}: {exc}"
            fetch_errors.append(warning)
            if args.strict_fetch:
                raise SystemExit(f"Strict fetch mode failed: {warning}") from exc
            continue
        for post in posts:
            post_id = str(post.get("id") or post.get("name") or post.get("permalink") or "")
            if not post_id:
                continue
            if post_id in seen:
                continue
            seen.add(post_id)
            all_posts.append(post)

    filtered_posts = filter_posts(
        all_posts,
        now_ts=now_ts,
        max_age_hours=max_age_hours,
        min_score=min_score,
        min_comments=min_comments,
        min_ratio=min_ratio,
        include_nsfw=args.include_nsfw,
    )

    strict_sentiment = build_asset_sentiment(
        assets,
        filtered_posts,
        now_ts=now_ts,
        recency_half_life_hours=recency_half_life_hours,
    )
    sentiment, fallback_meta = _apply_missing_group_fallback(
        assets=assets,
        all_posts=all_posts,
        strict_sentiment=strict_sentiment,
        now_ts=now_ts,
        max_age_hours=max_age_hours,
        recency_half_life_hours=recency_half_life_hours,
        include_nsfw=args.include_nsfw,
    )
    group_labels = {k: v.get("label", k) for k, v in (config.get("groups") or {}).items()}
    configured_assets: dict[str, list[str]] = {}
    for asset in assets:
        names = configured_assets.setdefault(asset.group, [])
        if asset.name not in names:
            names.append(asset.name)
    for names in configured_assets.values():
        names.sort()

    all_post_matches: list[PostMatch] = []
    for assets_list in sentiment.values():
        for item in assets_list:
            all_post_matches.extend(item.top_posts)

    if summarize_top > 0 and all_post_matches:
        summaries = summarize_urls(
            all_post_matches,
            top_n=summarize_top,
            model=summarize_model,
            length=summarize_length,
            max_tokens=summarize_max_tokens,
            firecrawl=summarize_firecrawl,
        )
        if summaries:
            for post in all_post_matches:
                if post.url in summaries:
                    post.summary = summaries[post.url]

    meta = {
        "generated_at": dt.datetime.fromtimestamp(now_ts, tz=tz).strftime("%Y-%m-%d %H:%M:%S"),
        "timezone": timezone,
        "groups": sorted(set([a.group for a in assets])),
        "filters": {
            "sort": sort,
            "time_filter": time_filter,
            "post_limit": post_limit,
            "max_age_hours": max_age_hours,
            "recency_half_life_hours": recency_half_life_hours,
            "min_score": min_score,
            "min_comments": min_comments,
            "min_upvote_ratio": min_ratio,
            "include_nsfw": args.include_nsfw,
            "summarize_top": summarize_top,
        },
        "counts": {
            "subreddits": len(subreddits),
            "subreddits_failed": len(fetch_errors),
            "subreddits_succeeded": max(0, len(subreddits) - len(fetch_errors)),
            "posts_seen": len(all_posts),
            "posts_filtered": len(filtered_posts),
        },
        "fallback": fallback_meta,
        "fetch_errors": fetch_errors,
        "configured_assets": configured_assets,
    }

    json_payload = {
        "meta": meta,
        "sentiment": {
            group: [dataclasses.asdict(item) for item in assets_list]
            for group, assets_list in sentiment.items()
        },
    }

    markdown_text = render_markdown(meta, sentiment, group_labels)
    json_text = json.dumps(json_payload, indent=2)

    if args.format == "both":
        base = resolve_base_path(args.out)
        json_path = base.with_suffix(".json")
        md_path = base.with_suffix(".md")
        json_path.parent.mkdir(parents=True, exist_ok=True)
        md_path.parent.mkdir(parents=True, exist_ok=True)
        json_path.write_text(json_text + "\n", encoding="utf-8")
        md_path.write_text(markdown_text + "\n", encoding="utf-8")
        print(f"Wrote {json_path}")
        print(f"Wrote {md_path}")
        if args.once_per_day:
            write_marker(marker_path, tz)
        return 0

    if args.out:
        Path(args.out).parent.mkdir(parents=True, exist_ok=True)
        Path(args.out).write_text(
            (json_text if args.format == "json" else markdown_text) + "\n",
            encoding="utf-8",
        )
    else:
        print(json_text if args.format == "json" else markdown_text)

    if args.once_per_day:
        write_marker(marker_path, tz)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
