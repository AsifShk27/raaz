from __future__ import annotations

from urllib.parse import urlparse, urlunparse
from typing import Dict, List, Sequence, Tuple

from rms_models import AssetSentiment, PostMatch


BULLISH_THRESHOLD = 0.28
BEARISH_THRESHOLD = -0.28


def _bias_label(score: float) -> str:
    if score >= BULLISH_THRESHOLD:
        return "Bullish"
    if score <= BEARISH_THRESHOLD:
        return "Bearish"
    return "Neutral"


def _format_signed(value: float) -> str:
    return f"{value:+.2f}"


def _escape_md_cell(value: str) -> str:
    return value.replace("\\", "\\\\").replace("|", "\\|").replace("\n", " ").strip()


def _truncate(text: str, max_len: int) -> str:
    if len(text) <= max_len:
        return text
    return text[: max_len - 3].rstrip() + "..."


def _normalize_url(url: str) -> str:
    raw = (url or "").strip()
    if not raw:
        return ""
    try:
        parsed = urlparse(raw)
    except ValueError:
        return raw

    scheme = parsed.scheme.lower() if parsed.scheme else "https"
    netloc = parsed.netloc.lower()
    if netloc.startswith("www."):
        netloc = netloc[4:]

    path = parsed.path or ""
    if path.endswith("/") and path != "/":
        path = path[:-1]
    return urlunparse((scheme, netloc, path, "", "", ""))


def _extract_post_id(url: str) -> str:
    normalized = _normalize_url(url)
    if not normalized:
        return ""

    parsed = urlparse(normalized)
    host = parsed.netloc.lower()
    parts = [segment for segment in parsed.path.split("/") if segment]

    if host == "redd.it" and parts:
        return parts[0]

    for index, segment in enumerate(parts):
        if segment == "comments" and index + 1 < len(parts):
            return parts[index + 1]
    return ""


def _post_dedupe_key(post: PostMatch) -> str:
    derived_id = _extract_post_id(str(post.url or ""))
    if derived_id:
        return f"id:{derived_id.lower()}"

    post_id = str(post.post_id or "").strip().lower()
    if post_id:
        return f"id:{post_id}"

    normalized = _normalize_url(str(post.url or ""))
    if normalized:
        return f"url:{normalized}"

    title = " ".join(str(post.title or "").lower().split())
    if title:
        return f"title:{title}"

    return ""


def _short_link(post: PostMatch) -> str:
    post_id = str(post.post_id or "").strip()
    if not post_id:
        post_id = _extract_post_id(str(post.url or ""))
    if post_id:
        return f"https://redd.it/{post_id}"

    normalized = _normalize_url(str(post.url or ""))
    if not normalized:
        return ""
    return _truncate(normalized, 56)


def _normalize_whitespace(text: str) -> str:
    return " ".join(str(text or "").split())


def _post_one_liner(post: PostMatch, max_len: int = 160) -> str:
    """Render a compact one-line explainer for chat delivery."""
    base = _normalize_whitespace(post.summary) if post.summary else _normalize_whitespace(post.title)
    if not base:
        base = "No title available."

    sentiment = _normalize_whitespace(post.sentiment_label).lower() or "neutral"
    subreddit = _normalize_whitespace(post.subreddit)
    context_parts: List[str] = []
    if subreddit:
        context_parts.append(f"r/{subreddit}")
    context_parts.append(sentiment)
    context_parts.append(f"impact {post.impact_score:.2f}")
    context = "; ".join(context_parts)
    return _truncate(f"{base} ({context})", max_len)


def _render_compact_table(
    headers: Sequence[str],
    rows: Sequence[Sequence[str]],
    right_align: Sequence[int] = (),
) -> List[str]:
    if not headers:
        return []

    width = len(headers)
    normalized_rows: List[List[str]] = []
    for row in rows:
        cells = [str(cell) for cell in row[:width]]
        if len(cells) < width:
            cells.extend([""] * (width - len(cells)))
        normalized_rows.append(cells)

    widths = [len(str(header)) for header in headers]
    for row in normalized_rows:
        for index, cell in enumerate(row):
            widths[index] = max(widths[index], len(cell))

    right = set(right_align)

    def pad(index: int, cell: str) -> str:
        target = widths[index]
        return cell.rjust(target) if index in right else cell.ljust(target)

    lines = [
        " | ".join(pad(index, str(header)) for index, header in enumerate(headers)),
        "-+-".join("-" * column for column in widths),
    ]

    for row in normalized_rows:
        lines.append(" | ".join(pad(index, cell) for index, cell in enumerate(row)))
    return lines


def _group_summary(assets: List[AssetSentiment]) -> Tuple[int, float, float]:
    total_mentions = sum(item.mentions for item in assets)
    if total_mentions <= 0:
        return 0, 0.0, 0.0
    weighted_sentiment = sum(item.avg_sentiment * item.mentions for item in assets) / total_mentions
    weighted_confidence = sum(item.confidence * item.mentions for item in assets) / total_mentions
    return total_mentions, weighted_sentiment, weighted_confidence


def _top_post_rows(assets: List[AssetSentiment], limit: int = 6) -> List[Tuple[str, PostMatch]]:
    deduped: Dict[str, Tuple[float, float, int, str, PostMatch]] = {}
    for item in assets:
        for post in item.top_posts:
            key = _post_dedupe_key(post)
            if not key:
                continue
            candidate = (post.impact_score, abs(post.sentiment), post.score, item.asset.name, post)
            existing = deduped.get(key)
            if existing is None or candidate[:3] > existing[:3]:
                deduped[key] = candidate

    ranked = sorted(deduped.values(), key=lambda row: (row[0], row[1], row[2]), reverse=True)
    return [(asset_name, post) for _, _, _, asset_name, post in ranked[:limit]]


def render_markdown(
    meta: dict,
    sentiment: Dict[str, List[AssetSentiment]],
    group_labels: Dict[str, str],
) -> str:
    lines: List[str] = []
    lines.append("# Reddit Market Sentiment")
    lines.append("")
    lines.append(f"Generated: {meta['generated_at']} ({meta['timezone']})")
    lines.append(f"Groups: {', '.join(meta['groups'])}")
    lines.append(
        (
            "Filters: sort={sort}, max_age={age}h, half_life={half_life}h, "
            "min_score={score}, min_comments={comments}"
        ).format(
            sort=meta["filters"]["sort"],
            age=meta["filters"]["max_age_hours"],
            half_life=meta["filters"]["recency_half_life_hours"],
            score=meta["filters"]["min_score"],
            comments=meta["filters"]["min_comments"],
        )
    )
    lines.append("")

    fetch_errors = [str(item) for item in (meta.get("fetch_errors") or []) if str(item).strip()]
    if fetch_errors:
        lines.append(f"Fetch warnings: {len(fetch_errors)} subreddit(s) could not be retrieved.")
        counts = meta.get("counts") or {}
        if counts.get("subreddits") and counts.get("subreddits_failed") == counts.get("subreddits"):
            lines.append("Coverage warning: all subreddit fetches failed; report is source-degraded.")
        lines.append("")
        lines.append("Warnings:")
        for warning in fetch_errors[:5]:
            lines.append(f"- {warning}")
        extra = len(fetch_errors) - 5
        if extra > 0:
            lines.append(f"- ... {extra} additional warning(s)")
        lines.append("")

    fallback = meta.get("fallback") or {}
    configured_assets = meta.get("configured_assets") or {}
    covered_groups = [str(group) for group in fallback.get("covered_groups", []) if str(group).strip()]
    requested_missing_groups = {
        str(group) for group in fallback.get("requested_missing_groups", []) if str(group).strip()
    }
    if covered_groups:
        lines.append(
            "Fallback coverage enabled for groups: {groups} "
            "(relaxed filters: min_score=0, min_comments=0, min_upvote_ratio=0.0).".format(
                groups=", ".join(covered_groups)
            )
        )
        lines.append("")

    configured_groups = [str(g) for g in meta.get("groups", []) if str(g).strip()]
    if not configured_groups:
        configured_groups = sorted(sentiment.keys())
    if not configured_groups:
        lines.append("No sentiment matches found for the current filters.")
        return "\n".join(lines)

    for group in configured_groups:
        assets = sentiment.get(group, [])
        label = group_labels.get(group, group)
        lines.append(f"## {label}")
        lines.append("")

        if not assets:
            tracked_assets = [str(name) for name in configured_assets.get(group, []) if str(name).strip()]
            if tracked_assets:
                lines.append("Tracked symbols for this group:")
                lines.append("")
                lines.append("```")
                lines.extend(
                    _render_compact_table(
                        headers=("Asset",),
                        rows=[[_escape_md_cell(name)] for name in tracked_assets],
                    )
                )
                lines.append("```")
                lines.append("")
            if group in requested_missing_groups:
                lines.append(
                    "No qualifying posts matched for this group under strict filters, and fallback "
                    "coverage found no candidates."
                )
            else:
                lines.append("No qualifying posts matched for this group under current filters.")
            lines.append("")
            continue

        if group in covered_groups:
            lines.append("Coverage mode: relaxed filters applied because strict filters returned no matches.")
            lines.append("")

        total_mentions, group_sentiment, group_confidence = _group_summary(assets)
        lines.append(
            "Summary: mentions={mentions}, bias={bias}, avg_sentiment={avg}, avg_confidence={conf}".format(
                mentions=total_mentions,
                bias=_bias_label(group_sentiment),
                avg=_format_signed(group_sentiment),
                conf=f"{group_confidence:.0%}",
            )
        )
        lines.append("")

        asset_rows = [
            [
                _escape_md_cell(item.asset.name),
                str(item.mentions),
                _bias_label(item.avg_sentiment),
                _format_signed(item.avg_sentiment),
                f"{item.confidence:.0%}",
                str(item.positive),
                str(item.negative),
                str(item.neutral),
            ]
            for item in assets
        ]
        lines.append("```")
        lines.extend(
            _render_compact_table(
                headers=("Asset", "Mentions", "Bias", "Avg", "Conf", "Bull", "Bear", "Neu"),
                rows=asset_rows,
                right_align=(1, 3, 4, 5, 6, 7),
            )
        )
        lines.append("```")
        lines.append("")

        top_rows = _top_post_rows(assets)
        lines.append("Top Articles (deduplicated):")
        lines.append("")

        if not top_rows:
            lines.append("No top articles available for this group.")
            lines.append("")
            continue

        for index, (_, post) in enumerate(top_rows, start=1):
            link = _short_link(post) or "N/A"
            one_liner = _post_one_liner(post)
            lines.append(f"{index}. {link} - {one_liner}")
        lines.append("")

    lines.append(
        "Notes: Multi-factor heuristic sentiment model "
        "(keyword, context, recency, engagement). Not financial advice."
    )
    return "\n".join(lines)
