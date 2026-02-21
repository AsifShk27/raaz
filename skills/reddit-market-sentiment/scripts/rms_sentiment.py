from __future__ import annotations

import math
import re
from typing import Dict, Iterable, List, Sequence, Tuple

from rms_models import AssetConfig, AssetSentiment, PostMatch


POS_WORDS = {
    "accumulate": 1.2,
    "beat": 1.3,
    "beats": 1.3,
    "breakout": 1.5,
    "bullish": 2.1,
    "buy": 1.6,
    "calls": 1.0,
    "call": 1.0,
    "cheap": 1.2,
    "conviction": 1.1,
    "growth": 0.8,
    "long": 1.2,
    "moon": 1.7,
    "outperform": 1.4,
    "overweight": 1.2,
    "profit": 0.9,
    "rally": 1.2,
    "rebound": 1.1,
    "strong": 1.0,
    "surge": 1.2,
    "undervalued": 1.4,
    "upgrade": 1.4,
}

NEG_WORDS = {
    "avoid": 1.2,
    "bagholder": 1.2,
    "bearish": 2.1,
    "breakdown": 1.5,
    "crash": 1.8,
    "cut": 1.0,
    "downgrade": 1.4,
    "dump": 1.6,
    "expensive": 1.0,
    "loss": 1.0,
    "miss": 1.3,
    "missed": 1.3,
    "overvalued": 1.4,
    "put": 1.0,
    "puts": 1.0,
    "sell": 1.6,
    "short": 1.2,
    "underperform": 1.4,
    "weak": 1.0,
}

PHRASE_SCORES: Sequence[Tuple[str, float]] = (
    (r"\bbeat(s|ing)? (earnings|estimates|expectations)\b", 1.8),
    (r"\bmiss(ed|es)? (earnings|estimates|expectations)\b", -1.8),
    (r"\bguide(d|s)? higher\b", 1.4),
    (r"\bguidance (raise|raised|up)\b", 1.4),
    (r"\bguidance (cut|lower|down)\b", -1.4),
    (r"\bprice target (raise|raised|upgrade)\b", 1.3),
    (r"\bprice target (cut|lower|downgrade)\b", -1.3),
    (r"\bshort squeeze\b", 1.4),
    (r"\bdead cat bounce\b", -1.3),
    (r"\bbuy the dip\b", 1.2),
    (r"\bsell the rip\b", -1.2),
)

NEGATIONS = {"not", "no", "never", "without", "isn't", "wasn't", "don't", "doesn't", "didn't", "can't"}
INTENSIFIERS = {"very", "extremely", "super", "massive", "huge", "big", "strong"}
HEDGES = {"maybe", "might", "could", "possibly", "unclear", "unsure", "speculative", "probably"}
SARCASM_MARKERS = {"/s", "lmao", "lol", "rofl"}

MARKET_CONTEXT_HINTS = {
    "analyst",
    "buy",
    "calls",
    "chart",
    "company",
    "earnings",
    "etf",
    "futures",
    "guidance",
    "long",
    "market",
    "options",
    "position",
    "price",
    "puts",
    "resistance",
    "revenue",
    "risk",
    "share",
    "short",
    "stock",
    "support",
    "target",
    "trade",
    "trend",
    "valuation",
    "volume",
}

TOKEN_RE = re.compile(r"[a-zA-Z$][a-zA-Z$0-9+.-]*")
SPACE_RE = re.compile(r"\s+")
SENTENCE_SPLIT_RE = re.compile(r"(?<=[.!?])\s+|\n+")


def clamp(value: float, low: float, high: float) -> float:
    return max(low, min(high, value))


def normalize_text(*parts: str | None) -> str:
    joined = "\n".join((part or "").strip() for part in parts if part)
    return SPACE_RE.sub(" ", joined).strip()


def tokenize(text: str) -> List[str]:
    return [token.lower() for token in TOKEN_RE.findall(text)]


def split_sentences(text: str) -> List[str]:
    if not text:
        return []
    chunks = [s.strip() for s in SENTENCE_SPLIT_RE.split(text) if s.strip()]
    return chunks if chunks else [text]


def lexical_signal_confidence(
    score: float,
    phrase_hits: int,
    polarity_hits: int,
    hedge_hits: int,
    token_count: int,
) -> float:
    magnitude = clamp(abs(score) / 0.55, 0.0, 1.0)
    phrase_factor = clamp(phrase_hits / 3.0, 0.0, 1.0)
    polarity_factor = clamp(polarity_hits / 6.0, 0.0, 1.0)
    size_factor = clamp(math.log1p(token_count) / math.log(40), 0.0, 1.0)
    hedge_penalty = clamp(1.0 - 0.18 * hedge_hits, 0.4, 1.0)
    confidence = (0.20 * magnitude) + (0.30 * phrase_factor) + (0.30 * polarity_factor) + (0.20 * size_factor)
    return clamp(confidence * hedge_penalty, 0.05, 0.99)


def sentiment_score(text: str) -> Tuple[float, str, float]:
    if not text:
        return 0.0, "neutral", 0.05

    lower_text = text.lower()
    score = 0.0
    phrase_hits = 0
    for pattern, weight in PHRASE_SCORES:
        if re.search(pattern, lower_text, flags=re.IGNORECASE):
            score += weight
            phrase_hits += 1

    tokens = tokenize(text)
    polarity_hits = 0
    hedge_hits = 0
    for idx, token in enumerate(tokens):
        if token in HEDGES:
            hedge_hits += 1
        weight = 0.0
        if token in POS_WORDS:
            weight = POS_WORDS[token]
        elif token in NEG_WORDS:
            weight = -NEG_WORDS[token]
        if weight == 0.0:
            continue

        polarity_hits += 1
        window = tokens[max(0, idx - 3): idx]
        if any(neg in window for neg in NEGATIONS):
            weight *= -1.0
        if any(intens in window for intens in INTENSIFIERS):
            weight *= 1.4
        score += weight

    if any(marker in lower_text for marker in SARCASM_MARKERS):
        score *= 0.75
    if hedge_hits:
        score *= clamp(1.0 - 0.10 * hedge_hits, 0.55, 1.0)

    norm = score / max(3.5, math.sqrt(max(len(tokens), 1)) * 1.1)
    norm = clamp(norm, -2.0, 2.0)

    if norm >= 0.28:
        label = "bullish"
    elif norm <= -0.28:
        label = "bearish"
    else:
        label = "neutral"

    confidence = lexical_signal_confidence(
        score=norm,
        phrase_hits=phrase_hits,
        polarity_hits=polarity_hits,
        hedge_hits=hedge_hits,
        token_count=len(tokens),
    )
    return norm, label, confidence


def keyword_patterns(asset: AssetConfig) -> List[Tuple[str, re.Pattern]]:
    patterns: List[Tuple[str, re.Pattern]] = []
    for raw in asset.keywords:
        keyword = raw.strip()
        if not keyword:
            continue
        escaped = re.escape(keyword).replace(r"\ ", r"\s+")
        flags = re.IGNORECASE
        if keyword.startswith("$"):
            pattern = rf"(?<![A-Za-z0-9]){escaped}(?![A-Za-z0-9])"
            flags = 0
        elif keyword.isupper() and len(keyword) <= 5:
            # Keep short tickers case-sensitive to avoid matching normal words
            # (for example SPY/spy, IT/it).
            pattern = rf"(?<![A-Za-z0-9])(?:\${escaped}|{escaped})(?![A-Za-z0-9])"
            flags = 0
        else:
            pattern = rf"(?<![A-Za-z0-9]){escaped}(?![A-Za-z0-9])"
        patterns.append((keyword, re.compile(pattern, flags)))
    return patterns


def market_context_present(text: str) -> bool:
    tokens = set(tokenize(text))
    return bool(tokens.intersection(MARKET_CONTEXT_HINTS))


def extract_asset_context(
    title: str,
    body: str,
    patterns: Sequence[Tuple[str, re.Pattern]],
) -> Tuple[str, List[str], bool]:
    combined = normalize_text(title, body)
    if not combined:
        return "", [], False

    sentences = split_sentences(combined)
    matched_keywords: set[str] = set()
    selected_sentences: List[str] = []

    for sentence in sentences:
        sentence_hit = False
        for keyword, pattern in patterns:
            if pattern.search(sentence):
                matched_keywords.add(keyword)
                sentence_hit = True
        if sentence_hit:
            selected_sentences.append(sentence)

    title_hit = False
    if title:
        for keyword, pattern in patterns:
            if pattern.search(title):
                title_hit = True
                matched_keywords.add(keyword)

    if not matched_keywords:
        return "", [], False

    if title_hit and title not in selected_sentences:
        selected_sentences.insert(0, title)
    if not selected_sentences:
        selected_sentences = [combined]

    context = " ".join(selected_sentences[:4])
    return context, sorted(matched_keywords), title_hit


def post_quality_weight(post: dict, now_ts: float, recency_half_life_hours: float) -> float:
    score = max(int(post.get("score") or 0), 0)
    comments = max(int(post.get("num_comments") or 0), 0)
    ratio = float(post.get("upvote_ratio") or 0.6)
    created_utc = float(post.get("created_utc") or now_ts)
    age_hours = max(0.0, (now_ts - created_utc) / 3600.0)

    engagement = 1.0 + math.log1p(score) + (0.55 * math.log1p(comments))
    half_life = max(1.0, recency_half_life_hours)
    recency = math.exp(-math.log(2.0) * age_hours / half_life)
    quality = clamp(0.80 + (0.40 * ratio), 0.70, 1.20)

    return max(0.2, engagement * recency * quality)


def is_low_signal_post(post: dict) -> bool:
    title = (post.get("title") or "").strip().lower()
    if not title or title in {"[removed]", "[deleted]"}:
        return True
    if post.get("stickied"):
        return True
    if post.get("is_video") and int(post.get("num_comments") or 0) == 0:
        return True
    return False


def filter_posts(
    posts: Iterable[dict],
    now_ts: float,
    max_age_hours: float,
    min_score: int,
    min_comments: int,
    min_ratio: float,
    include_nsfw: bool,
) -> List[dict]:
    filtered: List[dict] = []
    for post in posts:
        if is_low_signal_post(post):
            continue
        if not include_nsfw and post.get("over_18"):
            continue
        score = int(post.get("score") or 0)
        comments = int(post.get("num_comments") or 0)
        if score < min_score or comments < min_comments:
            continue
        ratio = post.get("upvote_ratio")
        if ratio is not None and float(ratio) < min_ratio:
            continue
        created_utc = float(post.get("created_utc") or 0)
        if created_utc <= 0:
            continue
        age_hours = (now_ts - created_utc) / 3600.0
        if age_hours < 0 or age_hours > max_age_hours:
            continue
        filtered.append(post)
    return filtered


def compute_asset_confidence(item: AssetSentiment) -> float:
    if item.mentions <= 0:
        return 0.0
    sample_factor = clamp(math.log1p(item.mentions) / math.log(12), 0.0, 1.0)
    dominant = max(item.positive, item.negative, item.neutral) / max(item.mentions, 1)
    magnitude = clamp(abs(item.avg_sentiment) / 0.50, 0.0, 1.0)
    confidence = (0.45 * sample_factor) + (0.30 * dominant) + (0.25 * magnitude)
    return clamp(confidence, 0.05, 0.99)


def build_asset_sentiment(
    assets: List[AssetConfig],
    posts: Iterable[dict],
    now_ts: float,
    recency_half_life_hours: float = 18.0,
) -> Dict[str, List[AssetSentiment]]:
    pattern_map = {asset.key: keyword_patterns(asset) for asset in assets}
    aggregated: Dict[str, Dict[str, AssetSentiment]] = {}

    for post in posts:
        title = (post.get("title") or "").strip()
        body = (post.get("selftext") or "").strip()
        permalink = str(post.get("permalink") or "")
        if not permalink:
            continue

        for asset in assets:
            context, matched_keywords, title_hit = extract_asset_context(title, body, pattern_map[asset.key])
            if not context:
                continue

            if not market_context_present(context):
                # Keep strict ticker/$ matches even when context words are sparse.
                strict_match = any(key.startswith("$") or (key.isupper() and len(key) <= 5) for key in matched_keywords)
                if not strict_match:
                    continue

            sentiment, label, lexical_conf = sentiment_score(context)
            if title_hit:
                sentiment *= 1.08
            quality_weight = post_quality_weight(post, now_ts=now_ts, recency_half_life_hours=recency_half_life_hours)
            impact_score = quality_weight * (0.45 + (0.55 * lexical_conf))

            bucket = aggregated.setdefault(asset.group, {})
            entry = bucket.get(asset.key)
            if entry is None:
                entry = AssetSentiment(
                    asset=asset,
                    mentions=0,
                    weighted_sentiment=0.0,
                    weight_total=0.0,
                    avg_sentiment=0.0,
                    positive=0,
                    negative=0,
                    neutral=0,
                    confidence=0.0,
                    directional_strength=0.0,
                    top_posts=[],
                )
                bucket[asset.key] = entry

            entry.mentions += 1
            entry.weighted_sentiment += sentiment * impact_score
            entry.weight_total += impact_score
            if label == "bullish":
                entry.positive += 1
            elif label == "bearish":
                entry.negative += 1
            else:
                entry.neutral += 1

            post_match = PostMatch(
                post_id=str(post.get("id") or ""),
                subreddit=str(post.get("subreddit") or ""),
                title=title,
                url=f"https://www.reddit.com{permalink}",
                score=int(post.get("score") or 0),
                comments=int(post.get("num_comments") or 0),
                created_utc=float(post.get("created_utc") or 0),
                sentiment=sentiment,
                sentiment_label=label,
                confidence=lexical_conf,
                impact_score=impact_score,
                matched_keywords=matched_keywords,
            )
            entry.top_posts.append(post_match)

    results: Dict[str, List[AssetSentiment]] = {}
    for group, assets_map in aggregated.items():
        items = list(assets_map.values())
        for item in items:
            if item.weight_total > 0:
                item.avg_sentiment = item.weighted_sentiment / item.weight_total
            item.confidence = compute_asset_confidence(item)
            item.directional_strength = abs(item.avg_sentiment) * item.confidence
            item.top_posts.sort(key=lambda p: (p.impact_score, abs(p.sentiment), p.score), reverse=True)
            item.top_posts = item.top_posts[:5]
        items.sort(key=lambda i: (i.directional_strength, i.mentions), reverse=True)
        results[group] = items
    return results
