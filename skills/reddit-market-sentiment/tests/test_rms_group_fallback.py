from __future__ import annotations

import sys
import time
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parents[1] / "scripts"
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from reddit_market_sentiment import _apply_missing_group_fallback
from rms_models import AssetConfig


def test_apply_missing_group_fallback_populates_empty_group_with_relaxed_filters() -> None:
    now_ts = time.time()
    assets = [AssetConfig(key="tcs", name="TCS", keywords=["TCS"], group="india")]
    all_posts = [
        {
            "id": "abc123",
            "permalink": "/r/IndianStockMarket/comments/abc123/tcs_outlook/",
            "title": "TCS outlook for next quarter",
            "selftext": "",
            "score": 0,
            "num_comments": 0,
            "upvote_ratio": 0.95,
            "created_utc": now_ts - 3600,
            "subreddit": "IndianStockMarket",
            "over_18": False,
        }
    ]

    sentiment, fallback = _apply_missing_group_fallback(
        assets=assets,
        all_posts=all_posts,
        strict_sentiment={},
        now_ts=now_ts,
        max_age_hours=72.0,
        recency_half_life_hours=18.0,
        include_nsfw=False,
    )

    assert fallback["applied"] is True
    assert fallback["covered_groups"] == ["india"]
    assert "india" in sentiment
    assert sentiment["india"]


def test_apply_missing_group_fallback_reports_uncovered_group_when_no_candidates() -> None:
    now_ts = time.time()
    assets = [AssetConfig(key="tcs", name="TCS", keywords=["TCS"], group="india")]

    sentiment, fallback = _apply_missing_group_fallback(
        assets=assets,
        all_posts=[],
        strict_sentiment={},
        now_ts=now_ts,
        max_age_hours=72.0,
        recency_half_life_hours=18.0,
        include_nsfw=False,
    )

    assert fallback["applied"] is False
    assert fallback["requested_missing_groups"] == ["india"]
    assert fallback["covered_groups"] == []
    assert sentiment == {}
