from __future__ import annotations

from typing import Any, List, Sequence


def render_markdown(meta: dict, trends: Sequence[Any]) -> str:
    lines: List[str] = []
    lines.append("# Reddit Trend Scout")
    lines.append("")
    lines.append(f"Generated: {meta['generated_at']} UTC")
    lines.append(f"Scope: {meta['scope']}")
    lines.append(f"Sort: {meta['sort']}  |  Time filter: {meta['time_filter']}")
    lines.append(f"Max age (hours): {meta['filters']['max_age_hours']}")
    lines.append(f"Minimums: score>={meta['filters']['min_score']}, comments>={meta['filters']['min_comments']}")
    if meta.get("fetch_errors"):
        lines.append(f"Fetch warnings: {len(meta['fetch_errors'])} subreddit(s) could not be retrieved.")
    lines.append("")

    if meta.get("fetch_errors"):
        lines.append("Warnings:")
        for warning in meta["fetch_errors"][:5]:
            lines.append(f"- {warning}")
        extra = len(meta["fetch_errors"]) - 5
        if extra > 0:
            lines.append(f"- ... {extra} additional warning(s)")
        lines.append("")

    if not trends:
        lines.append("No trends matched the filters.")
        return "\n".join(lines)

    for trend in trends:
        lines.append(f"## {trend.rank}. {trend.title}")
        lines.append("")
        lines.append(f"- Subreddit: {trend.subreddit} ({trend.subreddit_url})")
        lines.append(f"- Post: {trend.post_url}")
        if trend.external_url:
            lines.append(f"- External URL: {trend.external_url}")
        lines.append(
            "- Score: {score} | Comments: {comments} | Age: {age:.1f}h | Trend score: {score_val:.2f}".format(
                score=trend.score,
                comments=trend.comments,
                age=trend.age_hours,
                score_val=trend.trend_score,
            )
        )
        if trend.signals:
            lines.append(f"- Signals: {', '.join(trend.signals)}")
        if trend.snippet:
            lines.append(f"- Snippet: {trend.snippet}")
        lines.append("- Monetization angles:")
        for angle in trend.monetization_angles:
            lines.append(f"  - {angle}")
        lines.append("")

    lines.append("Notes:")
    lines.append("- Validate demand with opt-in surveys or landing pages and follow subreddit rules.")
    return "\n".join(lines)
