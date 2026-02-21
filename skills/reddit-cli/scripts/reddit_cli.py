#!/usr/bin/env python3
"""Dedicated Reddit CLI for robust subreddit fetch operations."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import sys
from pathlib import Path
from typing import Optional, Sequence


BASE_DIR = Path(__file__).resolve().parents[1]
LIB_DIR = BASE_DIR / "lib"
if str(LIB_DIR) not in sys.path:
    sys.path.insert(0, str(LIB_DIR))

from reddit_api import (  # noqa: E402
    DEFAULT_USER_AGENT,
    HttpClient,
    RedditAuth,
    RedditClient,
    fetch_posts,
    fetch_subreddits,
)


def parse_args(argv: Optional[Sequence[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Reddit CLI (structured JSON output).")
    subparsers = parser.add_subparsers(dest="command", required=True)

    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--auth", choices=["auto", "public", "app", "refresh"], default="auto")
    common.add_argument("--client-id", default=os.environ.get("REDDIT_CLIENT_ID"))
    common.add_argument("--client-secret", default=os.environ.get("REDDIT_CLIENT_SECRET"))
    common.add_argument("--refresh-token", default=os.environ.get("REDDIT_REFRESH_TOKEN"))
    common.add_argument("--user-agent", default=DEFAULT_USER_AGENT)
    common.add_argument("--timeout", type=int, default=30)
    common.add_argument("--max-retries", type=int, default=4)
    common.add_argument("--sleep-ms", type=int, default=150)
    common.add_argument("--format", choices=["json", "pretty"], default="json")

    check = subparsers.add_parser("check", parents=[common], help="Validate connectivity/auth mode.")
    check.add_argument("--path", default="/r/reddit/about.json", help="Health path to request.")

    posts = subparsers.add_parser("posts", parents=[common], help="Fetch posts from subreddit.")
    posts.add_argument("--subreddit", required=True, help="Subreddit name without r/ prefix.")
    posts.add_argument("--sort", choices=["hot", "new", "rising", "top"], default="new")
    posts.add_argument("--time", dest="time_filter", default="day")
    posts.add_argument("--limit", type=int, default=25)

    subreddits = subparsers.add_parser("subreddits", parents=[common], help="List subreddit names.")
    subreddits.add_argument("--where", choices=["popular", "new"], default="popular")
    subreddits.add_argument("--limit", type=int, default=25)

    return parser.parse_args(argv)


def build_client(args: argparse.Namespace) -> RedditClient:
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
    return RedditClient(http=http, auth=auth)


def emit(payload: dict, output_format: str) -> None:
    if output_format == "pretty":
        print(json.dumps(payload, indent=2))
        return
    print(json.dumps(payload, separators=(",", ":")))


def command_check(client: RedditClient, args: argparse.Namespace) -> dict:
    payload = client.get_json(args.path)
    return {
        "ok": True,
        "generated_at_utc": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%d %H:%M:%S"),
        "auth_mode_requested": args.auth,
        "auth_mode_effective": client.auth.effective_mode(),
        "endpoint": args.path,
        "top_level_keys": sorted(payload.keys()),
    }


def command_posts(client: RedditClient, args: argparse.Namespace) -> dict:
    posts = fetch_posts(
        client=client,
        subreddit=args.subreddit.lstrip("r/"),
        sort=args.sort,
        time_filter=args.time_filter,
        limit=args.limit,
    )
    return {
        "meta": {
            "generated_at_utc": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%d %H:%M:%S"),
            "auth_mode_requested": args.auth,
            "auth_mode_effective": client.auth.effective_mode(),
            "subreddit": args.subreddit.lstrip("r/"),
            "sort": args.sort,
            "time_filter": args.time_filter,
            "limit": args.limit,
            "count": len(posts),
        },
        "posts": posts,
    }


def command_subreddits(client: RedditClient, args: argparse.Namespace) -> dict:
    subreddits = fetch_subreddits(client=client, where=args.where, limit=args.limit)
    return {
        "meta": {
            "generated_at_utc": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%d %H:%M:%S"),
            "auth_mode_requested": args.auth,
            "auth_mode_effective": client.auth.effective_mode(),
            "where": args.where,
            "limit": args.limit,
            "count": len(subreddits),
        },
        "subreddits": subreddits,
    }


def main(argv: Optional[Sequence[str]] = None) -> int:
    args = parse_args(argv)
    client = build_client(args)

    if args.command == "check":
        payload = command_check(client, args)
        emit(payload, args.format)
        return 0
    if args.command == "posts":
        payload = command_posts(client, args)
        emit(payload, args.format)
        return 0
    if args.command == "subreddits":
        payload = command_subreddits(client, args)
        emit(payload, args.format)
        return 0

    raise RuntimeError(f"Unsupported command: {args.command}")


if __name__ == "__main__":
    raise SystemExit(main())
