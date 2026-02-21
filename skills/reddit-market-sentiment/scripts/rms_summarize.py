from __future__ import annotations

import math
import os
import shutil
import subprocess
import time
from typing import Dict, Iterable, List, Optional, Tuple

from rms_models import PostMatch


def summarize_urls(
    posts: Iterable[PostMatch],
    top_n: int,
    model: Optional[str],
    length: Optional[str],
    max_tokens: Optional[int],
    firecrawl: Optional[str],
) -> Dict[str, str]:
    if top_n <= 0:
        return {}
    if shutil.which("summarize") is None:
        print("[warn] summarize CLI not found; skipping summaries")
        return {}

    scored: List[Tuple[float, PostMatch]] = []
    for post in posts:
        priority = abs(post.sentiment) * math.log1p(max(post.score + post.comments, 0))
        scored.append((priority, post))
    scored.sort(key=lambda item: item[0], reverse=True)

    per_url_timeout = int(os.environ.get("RMS_SUMMARIZE_TIMEOUT_SECONDS", "25"))
    max_total_seconds = int(os.environ.get("RMS_SUMMARIZE_MAX_TOTAL_SECONDS", "120"))
    started_at = time.monotonic()

    summary_cache: Dict[str, str] = {}
    seen: set[str] = set()
    for _, post in scored:
        if time.monotonic() - started_at >= max_total_seconds:
            print("[warn] summarize time budget exhausted; continuing without more summaries")
            break
        if len(summary_cache) >= top_n:
            break
        if not post.url or post.url in seen:
            continue
        seen.add(post.url)
        summary = summarize_url(
            post.url,
            model=model,
            length=length,
            max_tokens=max_tokens,
            firecrawl=firecrawl,
            timeout_seconds=per_url_timeout,
        )
        if summary:
            summary_cache[post.url] = summary
    return summary_cache


def summarize_url(
    url: str,
    model: Optional[str],
    length: Optional[str],
    max_tokens: Optional[int],
    firecrawl: Optional[str],
    timeout_seconds: int,
) -> Optional[str]:
    cmd = ["summarize", url]
    if model:
        cmd += ["--model", model]
    if length:
        cmd += ["--length", length]
    if max_tokens:
        cmd += ["--max-output-tokens", str(max_tokens)]
    if firecrawl:
        cmd += ["--firecrawl", firecrawl]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=max(5, timeout_seconds))
    except Exception as exc:
        print(f"[warn] summarize failed for {url}: {exc}")
        return None
    if result.returncode != 0:
        stderr = (result.stderr or "").strip()
        print(f"[warn] summarize failed for {url}: {stderr[:200]}")
        return None
    return (result.stdout or "").strip() or None
