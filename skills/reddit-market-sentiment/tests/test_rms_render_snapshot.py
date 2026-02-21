from __future__ import annotations

import sys
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parents[1] / "scripts"
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from rms_models import AssetConfig, AssetSentiment, PostMatch
from rms_render import render_markdown


def _meta() -> dict:
    return {
        "generated_at": "2026-02-14 18:10:00",
        "timezone": "Asia/Kolkata",
        "groups": ["us"],
        "filters": {
            "sort": "new",
            "max_age_hours": 24,
            "recency_half_life_hours": 18,
            "min_score": 5,
            "min_comments": 2,
        },
    }


def _sentiment_fixture() -> dict[str, list[AssetSentiment]]:
    asset_one = AssetConfig(key="asset1", name="Asset One | Equity", keywords=["A1"], group="us")
    asset_two = AssetConfig(key="asset2", name="Asset Two", keywords=["A2"], group="us")

    post_one = PostMatch(
        post_id="p1",
        subreddit="stocks",
        title="Asset One breaks out [analysis] | setup",
        url="https://www.reddit.com/r/stocks/comments/p1",
        score=120,
        comments=55,
        created_utc=0,
        sentiment=0.61,
        sentiment_label="bullish",
        confidence=0.91,
        impact_score=7.25,
        matched_keywords=["A1"],
        summary="Momentum appears durable on volume expansion.",
    )
    post_shared_low = PostMatch(
        post_id="p_shared_low",
        subreddit="investing",
        title="Macro thread around Asset One and Asset Two",
        url="https://www.reddit.com/r/investing/comments/shared",
        score=44,
        comments=18,
        created_utc=0,
        sentiment=-0.20,
        sentiment_label="bearish",
        confidence=0.58,
        impact_score=2.10,
        matched_keywords=["A1"],
    )
    post_two = PostMatch(
        post_id="p2",
        subreddit="wallstreetbets",
        title="Asset Two downside risk discussion",
        url="https://www.reddit.com/r/wallstreetbets/comments/p2",
        score=90,
        comments=70,
        created_utc=0,
        sentiment=-0.44,
        sentiment_label="bearish",
        confidence=0.88,
        impact_score=6.50,
        matched_keywords=["A2"],
    )
    post_shared_high = PostMatch(
        post_id="p_shared_high",
        subreddit="investing",
        title="Macro thread around Asset One and Asset Two",
        url="https://www.reddit.com/r/investing/comments/shared",
        score=52,
        comments=21,
        created_utc=0,
        sentiment=-0.31,
        sentiment_label="bearish",
        confidence=0.62,
        impact_score=3.20,
        matched_keywords=["A2"],
    )

    first = AssetSentiment(
        asset=asset_one,
        mentions=2,
        weighted_sentiment=0.84,
        weight_total=2.0,
        avg_sentiment=0.42,
        positive=2,
        negative=0,
        neutral=0,
        confidence=0.81,
        directional_strength=0.34,
        top_posts=[post_one, post_shared_low],
    )
    second = AssetSentiment(
        asset=asset_two,
        mentions=1,
        weighted_sentiment=-0.35,
        weight_total=1.0,
        avg_sentiment=-0.35,
        positive=0,
        negative=1,
        neutral=0,
        confidence=0.74,
        directional_strength=0.26,
        top_posts=[post_two, post_shared_high],
    )

    return {"us": [first, second]}


def test_render_markdown_snapshot_tables() -> None:
    actual = render_markdown(_meta(), _sentiment_fixture(), {"us": "US Equities"})
    expected = """# Reddit Market Sentiment

Generated: 2026-02-14 18:10:00 (Asia/Kolkata)
Groups: us
Filters: sort=new, max_age=24h, half_life=18h, min_score=5, min_comments=2

## US Equities

Summary: mentions=3, bias=Neutral, avg_sentiment=+0.16, avg_confidence=79%

```
Asset               | Mentions | Bias    |   Avg | Conf | Bull | Bear | Neu
--------------------+----------+---------+-------+------+------+------+----
Asset One \\| Equity |        2 | Bullish | +0.42 |  81% |    2 |    0 |   0
Asset Two           |        1 | Bearish | -0.35 |  74% |    0 |    1 |   0
```

Top Articles (deduplicated):

1. https://redd.it/p1 - Momentum appears durable on volume expansion. (r/stocks; bullish; impact 7.25)
2. https://redd.it/p2 - Asset Two downside risk discussion (r/wallstreetbets; bearish; impact 6.50)
3. https://redd.it/p_shared_high - Macro thread around Asset One and Asset Two (r/investing; bearish; impact 3.20)

Notes: Multi-factor heuristic sentiment model (keyword, context, recency, engagement). Not financial advice."""
    assert actual == expected


def test_render_markdown_no_matches_message() -> None:
    text = render_markdown(_meta(), {}, {"us": "US Equities"})
    assert "## US Equities" in text
    assert "No qualifying posts matched for this group under current filters." in text


def test_render_markdown_no_matches_shows_configured_symbols() -> None:
    meta = _meta()
    meta["configured_assets"] = {"us": ["AAPL", "MSFT"]}
    text = render_markdown(meta, {}, {"us": "US Equities"})
    assert "Tracked symbols for this group:" in text
    assert "AAPL" in text
    assert "MSFT" in text


def test_render_markdown_includes_empty_requested_group() -> None:
    meta = _meta()
    meta["groups"] = ["us", "india"]
    text = render_markdown(meta, _sentiment_fixture(), {"us": "US Equities", "india": "India Equities"})
    assert "## US Equities" in text
    assert "## India Equities" in text
    assert "No qualifying posts matched for this group under current filters." in text


def test_render_markdown_fallback_coverage_annotations() -> None:
    meta = _meta()
    meta["fallback"] = {
        "applied": True,
        "requested_missing_groups": ["us"],
        "covered_groups": ["us"],
        "relaxed_filters": {"min_score": 0, "min_comments": 0, "min_upvote_ratio": 0.0},
    }
    text = render_markdown(meta, _sentiment_fixture(), {"us": "US Equities"})
    assert "Fallback coverage enabled for groups: us" in text
    assert "Coverage mode: relaxed filters applied because strict filters returned no matches." in text


def test_render_markdown_fallback_reports_no_candidates() -> None:
    meta = _meta()
    meta["groups"] = ["us", "india"]
    meta["fallback"] = {
        "applied": False,
        "requested_missing_groups": ["india"],
        "covered_groups": [],
        "relaxed_filters": {"min_score": 0, "min_comments": 0, "min_upvote_ratio": 0.0},
    }
    text = render_markdown(meta, _sentiment_fixture(), {"us": "US Equities", "india": "India Equities"})
    assert "## India Equities" in text
    assert "fallback coverage found no candidates" in text
