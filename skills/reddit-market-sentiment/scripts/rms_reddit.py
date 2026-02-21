from __future__ import annotations

import sys
from pathlib import Path


SKILLS_DIR = Path(__file__).resolve().parents[2]
REDDIT_CLI_LIB_DIR = SKILLS_DIR / "reddit-cli" / "lib"
if str(REDDIT_CLI_LIB_DIR) not in sys.path:
    sys.path.insert(0, str(REDDIT_CLI_LIB_DIR))

from reddit_api import (  # noqa: E402,F401
    DEFAULT_USER_AGENT,
    HttpClient,
    RedditAuth,
    RedditClient,
    fetch_posts,
)


__all__ = [
    "DEFAULT_USER_AGENT",
    "HttpClient",
    "RedditAuth",
    "RedditClient",
    "fetch_posts",
]
