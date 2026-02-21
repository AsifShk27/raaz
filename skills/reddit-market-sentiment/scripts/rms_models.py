from __future__ import annotations

from dataclasses import dataclass, field
from typing import List, Optional


@dataclass
class AssetConfig:
    key: str
    name: str
    keywords: List[str]
    group: str


@dataclass
class PostMatch:
    post_id: str
    subreddit: str
    title: str
    url: str
    score: int
    comments: int
    created_utc: float
    sentiment: float
    sentiment_label: str
    confidence: float = 0.0
    impact_score: float = 0.0
    matched_keywords: List[str] = field(default_factory=list)
    summary: Optional[str] = None


@dataclass
class AssetSentiment:
    asset: AssetConfig
    mentions: int
    weighted_sentiment: float
    weight_total: float
    avg_sentiment: float
    positive: int
    negative: int
    neutral: int
    confidence: float
    directional_strength: float
    top_posts: List[PostMatch]
