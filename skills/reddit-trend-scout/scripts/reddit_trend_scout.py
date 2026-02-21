#!/usr/bin/env python3
"""Reddit Trend Scout: find fast-rising posts and generate monetization angles."""

from __future__ import annotations

import argparse
import dataclasses
import datetime as dt
import json
import os
import re
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Sequence, Tuple

SKILLS_DIR = Path(__file__).resolve().parents[2]
REDDIT_CLI_LIB_DIR = SKILLS_DIR / "reddit-cli" / "lib"
if str(REDDIT_CLI_LIB_DIR) not in sys.path:
    sys.path.insert(0, str(REDDIT_CLI_LIB_DIR))

from reddit_api import (  # noqa: E402
    DEFAULT_USER_AGENT,
    HttpClient,
    RedditAuth,
    RedditClient,
    fetch_posts,
    fetch_subreddits,
)
from trend_render import render_markdown

SIGNAL_PATTERNS: Dict[str, Sequence[str]] = {
    "buyer_intent": [
        r"\bbest\b",
        r"\brecommend",
        r"\blooking for\b",
        r"\bwhere to buy\b",
        r"\bwhich (one|tool|service)\b",
        r"\banyone tried\b",
        r"\bworth it\b",
    ],
    "pain_point": [
        r"\bproblem\b",
        r"\bissue\b",
        r"\bstruggl\w*\b",
        r"\bfrustrat\w*\b",
        r"\bdoesn't work\b",
        r"\bfix\b",
        r"\bhelp\b",
    ],
    "workflow_gap": [
        r"\bworkflow\b",
        r"\bautomate\b",
        r"\bscript\b",
        r"\btool\b",
        r"\bplugin\b",
        r"\bintegration\b",
        r"\bapi\b",
    ],
    "learning": [
        r"\bhow do i\b",
        r"\bguide\b",
        r"\btutorial\b",
        r"\bbeginner\b",
        r"\bsteps\b",
        r"\bexplain\b",
    ],
    "pricing": [
        r"\bprice\b",
        r"\bcost\b",
        r"\bexpensive\b",
        r"\baffordable\b",
        r"\bbudget\b",
        r"\bcheap\b",
    ],
}

FLAIR_HINTS: Dict[str, str] = {
    "question": "learning",
    "help": "pain_point",
    "request": "buyer_intent",
    "recommend": "buyer_intent",
    "wtb": "buyer_intent",
    "looking": "buyer_intent",
}

MONETIZATION_ANGLES: Dict[str, Sequence[str]] = {
    "buyer_intent": [
        "Build a comparison guide or curated shortlist with affiliate/partner links (only where allowed).",
        "Offer a direct product bundle or starter kit that matches the request.",
    ],
    "pain_point": [
        "Create a paid tool, automation, or service that removes the bottleneck.",
        "Offer a troubleshooting or setup service with a clear scope and price.",
    ],
    "workflow_gap": [
        "Ship a micro-SaaS, plugin, or script pack that compresses the workflow.",
        "Sell templates, checklists, or SOPs that speed up the task.",
    ],
    "learning": [
        "Launch a paid guide, workshop, or course tailored to beginners.",
        "Create a newsletter or library of best practices and charge for access.",
    ],
    "pricing": [
        "Position a freemium or tiered offer emphasizing cost savings.",
        "Create a price tracker or budget alternative list.",
    ],
}


@dataclass
class Trend:
    rank: int
    trend_score: float
    score: int
    comments: int
    age_hours: float
    score_per_hour: float
    comments_per_hour: float
    upvote_ratio: Optional[float]
    subreddit: str
    subreddit_url: str
    subreddit_subscribers: Optional[int]
    title: str
    post_url: str
    external_url: Optional[str]
    snippet: Optional[str]
    signals: List[str]
    signal_evidence: Dict[str, List[str]]
    monetization_angles: List[str]
    niche_label: str

def _parse_subreddits(raw: Optional[str]) -> List[str]:
    if not raw:
        return []
    return [item.strip().lstrip("r/") for item in raw.split(",") if item.strip()]


def _read_subreddits_file(path: Optional[str]) -> List[str]:
    if not path:
        return []
    data = Path(path).read_text(encoding="utf-8")
    subs = []
    for line in data.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        subs.append(line.lstrip("r/"))
    return subs


def _normalize_text(*parts: Optional[str]) -> str:
    return "\n".join(part for part in parts if part).lower()


def _extract_signals(text: str, flair: Optional[str]) -> Tuple[List[str], Dict[str, List[str]]]:
    evidence: Dict[str, List[str]] = {}
    signals: List[str] = []
    for signal, patterns in SIGNAL_PATTERNS.items():
        matches: List[str] = []
        for pattern in patterns:
            match = re.search(pattern, text, flags=re.IGNORECASE)
            if match:
                matches.append(match.group(0))
        if matches:
            signals.append(signal)
            evidence[signal] = matches

    if flair:
        flair_lower = flair.lower()
        for key, signal in FLAIR_HINTS.items():
            if key in flair_lower and signal not in signals:
                signals.append(signal)
                evidence.setdefault(signal, []).append(flair)

    return signals, evidence


def _niche_label(subscribers: Optional[int]) -> str:
    if subscribers is None:
        return "unknown"
    if subscribers < 50_000:
        return "niche"
    if subscribers < 250_000:
        return "mid"
    if subscribers < 1_000_000:
        return "large"
    return "very_large"


def _niche_weight(subscribers: Optional[int]) -> float:
    if subscribers is None:
        return 1.0
    if subscribers < 50_000:
        return 1.25
    if subscribers < 250_000:
        return 1.05
    if subscribers < 1_000_000:
        return 0.9
    return 0.75


def _build_angles(signals: List[str]) -> List[str]:
    angles: List[str] = []
    seen = set()
    for signal in signals:
        for angle in MONETIZATION_ANGLES.get(signal, []):
            if angle not in seen:
                angles.append(angle)
                seen.add(angle)
    if not angles:
        angles.append("Collect more examples to validate demand before building.")
    return angles


def _snippet(text: Optional[str], limit: int = 240) -> Optional[str]:
    if not text:
        return None
    clean = " ".join(text.split())
    if len(clean) <= limit:
        return clean
    return clean[: max(0, limit - 3)] + "..."


def build_trends(
    posts: Iterable[dict],
    now_ts: float,
    max_age_hours: float,
    min_score: int,
    min_comments: int,
    min_ratio: float,
    include_nsfw: bool,
) -> List[Trend]:
    trends: List[Trend] = []
    for post in posts:
        if not include_nsfw and post.get("over_18"):
            continue
        score = int(post.get("score") or 0)
        comments = int(post.get("num_comments") or 0)
        if score < min_score or comments < min_comments:
            continue
        upvote_ratio = post.get("upvote_ratio")
        if upvote_ratio is not None and upvote_ratio < min_ratio:
            continue
        created_utc = float(post.get("created_utc") or 0)
        if created_utc <= 0:
            continue
        age_hours = max((now_ts - created_utc) / 3600.0, 0.25)
        if age_hours > max_age_hours:
            continue

        score_rate = max(score, 0) / age_hours
        comments_rate = max(comments, 0) / age_hours
        ratio_weight = 0.8 + (upvote_ratio if upvote_ratio is not None else 0.5) * 0.4
        niche_weight = _niche_weight(post.get("subreddit_subscribers"))
        trend_score = (score_rate * 0.6 + comments_rate * 0.4) * ratio_weight * niche_weight

        title = post.get("title") or ""
        selftext = post.get("selftext") or ""
        flair = post.get("link_flair_text")
        text = _normalize_text(title, selftext, flair)
        signals, evidence = _extract_signals(text, flair)
        angles = _build_angles(signals)

        subreddit = post.get("subreddit") or ""
        permalink = post.get("permalink") or ""
        post_url = f"https://www.reddit.com{permalink}" if permalink else ""
        external_url = post.get("url")
        if external_url == post_url:
            external_url = None

        trends.append(
            Trend(
                rank=0,
                trend_score=trend_score,
                score=score,
                comments=comments,
                age_hours=age_hours,
                score_per_hour=score_rate,
                comments_per_hour=comments_rate,
                upvote_ratio=upvote_ratio,
                subreddit=f"r/{subreddit}" if subreddit else "",
                subreddit_url=f"https://www.reddit.com/r/{subreddit}/" if subreddit else "",
                subreddit_subscribers=post.get("subreddit_subscribers"),
                title=title,
                post_url=post_url,
                external_url=external_url,
                snippet=_snippet(selftext),
                signals=signals,
                signal_evidence=evidence,
                monetization_angles=angles,
                niche_label=_niche_label(post.get("subreddit_subscribers")),
            )
        )

    trends.sort(key=lambda item: item.trend_score, reverse=True)
    for idx, trend in enumerate(trends, start=1):
        trend.rank = idx
    return trends


def parse_args(argv: Optional[Sequence[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Scan Reddit trends and monetization angles.")
    parser.add_argument("--scope", choices=["popular", "all", "custom"], default="popular")
    parser.add_argument("--subreddits", help="Comma-separated list of subreddits")
    parser.add_argument("--subreddits-file", help="Path to file with one subreddit per line")
    parser.add_argument("--discover-subreddits", choices=["popular", "new"], help="Fetch subreddit list")
    parser.add_argument("--subreddit-limit", type=int, default=20)
    parser.add_argument("--sort", choices=["hot", "new", "rising", "top"], default="hot")
    parser.add_argument("--time", dest="time_filter", default="day")
    parser.add_argument("--post-limit", type=int, default=30)
    parser.add_argument("--trend-limit", type=int, default=20)
    parser.add_argument("--max-age-hours", type=float, default=72.0)
    parser.add_argument("--min-score", type=int, default=10)
    parser.add_argument("--min-comments", type=int, default=5)
    parser.add_argument("--min-upvote-ratio", type=float, default=0.6)
    parser.add_argument("--include-nsfw", action="store_true")
    parser.add_argument("--format", choices=["md", "json", "both"], default="md")
    parser.add_argument("--out", help="Output file path (or prefix when using --format both)")
    parser.add_argument("--auth", choices=["auto", "public", "app", "refresh"], default="auto")
    parser.add_argument("--client-id", default=os.environ.get("REDDIT_CLIENT_ID"))
    parser.add_argument("--client-secret", default=os.environ.get("REDDIT_CLIENT_SECRET"))
    parser.add_argument("--refresh-token", default=os.environ.get("REDDIT_REFRESH_TOKEN"))
    parser.add_argument("--user-agent", default=DEFAULT_USER_AGENT)
    parser.add_argument("--timeout", type=int, default=30)
    parser.add_argument("--max-retries", type=int, default=4)
    parser.add_argument("--sleep-ms", type=int, default=150)
    parser.add_argument(
        "--strict-fetch",
        action="store_true",
        help="Fail the run if any subreddit fetch fails (default: continue with warnings).",
    )
    return parser.parse_args(argv)


def main(argv: Optional[Sequence[str]] = None) -> int:
    args = parse_args(argv)

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

    explicit_subs = _parse_subreddits(args.subreddits)
    explicit_subs.extend(_read_subreddits_file(args.subreddits_file))
    explicit_subs = list(dict.fromkeys(explicit_subs))
    fetch_errors: List[str] = []

    if args.scope == "custom" and not explicit_subs and not args.discover_subreddits:
        raise SystemExit("--scope custom requires --subreddits, --subreddits-file, or --discover-subreddits")

    posts: List[dict] = []
    if explicit_subs:
        for sub in explicit_subs:
            try:
                posts.extend(fetch_posts(client, sub, args.sort, args.time_filter, args.post_limit))
            except RuntimeError as exc:
                fetch_errors.append(f"r/{sub}: {exc}")
                if args.strict_fetch:
                    raise
        scope_label = "custom"
    elif args.discover_subreddits:
        discovered = fetch_subreddits(client, args.discover_subreddits, args.subreddit_limit)
        for sub in discovered:
            try:
                posts.extend(fetch_posts(client, sub, args.sort, args.time_filter, args.post_limit))
            except RuntimeError as exc:
                fetch_errors.append(f"r/{sub}: {exc}")
                if args.strict_fetch:
                    raise
        scope_label = f"discover:{args.discover_subreddits}"
        explicit_subs = discovered
    else:
        scope_label = args.scope
        try:
            posts.extend(fetch_posts(client, args.scope, args.sort, args.time_filter, args.post_limit))
        except RuntimeError as exc:
            fetch_errors.append(f"r/{args.scope}: {exc}")
            if args.strict_fetch:
                raise

    now_ts = time.time()
    trends = build_trends(
        posts,
        now_ts=now_ts,
        max_age_hours=args.max_age_hours,
        min_score=args.min_score,
        min_comments=args.min_comments,
        min_ratio=args.min_upvote_ratio,
        include_nsfw=args.include_nsfw,
    )

    trends = trends[: args.trend_limit]

    meta = {
        "generated_at": dt.datetime.fromtimestamp(now_ts, tz=dt.timezone.utc).strftime("%Y-%m-%d %H:%M:%S"),
        "scope": scope_label,
        "sort": args.sort,
        "time_filter": args.time_filter,
        "subreddits": explicit_subs,
        "filters": {
            "max_age_hours": args.max_age_hours,
            "min_score": args.min_score,
            "min_comments": args.min_comments,
            "min_upvote_ratio": args.min_upvote_ratio,
            "include_nsfw": args.include_nsfw,
        },
        "counts": {
            "posts_seen": len(posts),
            "trends_returned": len(trends),
        },
        "fetch_errors": fetch_errors,
    }

    json_payload = {
        "meta": meta,
        "trends": [dataclasses.asdict(trend) for trend in trends],
    }

    if args.format in {"json", "both"}:
        json_text = json.dumps(json_payload, indent=2)
    else:
        json_text = ""

    if args.format in {"md", "both"}:
        markdown_text = render_markdown(meta, trends)
    else:
        markdown_text = ""

    if args.format == "both":
        base = _resolve_base_path(args.out)
        json_path = base.with_suffix(".json")
        md_path = base.with_suffix(".md")
        json_path.parent.mkdir(parents=True, exist_ok=True)
        md_path.parent.mkdir(parents=True, exist_ok=True)
        json_path.write_text(json_text + "\n", encoding="utf-8")
        md_path.write_text(markdown_text + "\n", encoding="utf-8")
        print(f"Wrote {json_path}")
        print(f"Wrote {md_path}")
        return 0

    if args.out:
        Path(args.out).parent.mkdir(parents=True, exist_ok=True)
        Path(args.out).write_text(
            (json_text if args.format == "json" else markdown_text) + "\n",
            encoding="utf-8",
        )
    else:
        print(json_text if args.format == "json" else markdown_text)

    return 0


def _resolve_base_path(out_path: Optional[str]) -> Path:
    if out_path:
        path = Path(out_path)
        if path.suffix:
            return path.with_suffix("")
        return path
    timestamp = dt.datetime.utcnow().strftime("%Y%m%d-%H%M%S")
    return Path.cwd() / f"reddit-trends-{timestamp}"


if __name__ == "__main__":
    raise SystemExit(main())
