from __future__ import annotations

import sys
from pathlib import Path


LIB_DIR = Path(__file__).resolve().parents[1] / "lib"
if str(LIB_DIR) not in sys.path:
    sys.path.insert(0, str(LIB_DIR))

from reddit_api import HttpClient, RedditAuth, RedditClient


def test_auto_auth_without_creds_falls_back_to_public() -> None:
    http = HttpClient(user_agent="ua", timeout=1, max_retries=1)
    auth = RedditAuth(http=http, auth_mode="auto", client_id=None, client_secret=None, refresh_token=None)
    assert auth.effective_mode() == "public"
    assert auth.enabled() is False


def test_auto_auth_prefers_refresh_when_token_present() -> None:
    http = HttpClient(user_agent="ua", timeout=1, max_retries=1)
    auth = RedditAuth(http=http, auth_mode="auto", client_id="id", client_secret="secret", refresh_token="rtok")
    assert auth.effective_mode() == "refresh"
    assert auth.enabled() is True


def test_auto_auth_uses_app_when_refresh_missing() -> None:
    http = HttpClient(user_agent="ua", timeout=1, max_retries=1)
    auth = RedditAuth(http=http, auth_mode="auto", client_id="id", client_secret="secret", refresh_token=None)
    assert auth.effective_mode() == "app"
    assert auth.enabled() is True


def test_client_base_url_respects_effective_mode() -> None:
    http = HttpClient(user_agent="ua", timeout=1, max_retries=1)

    public_auth = RedditAuth(http=http, auth_mode="public", client_id=None, client_secret=None, refresh_token=None)
    public_client = RedditClient(http=http, auth=public_auth)
    assert public_client.base_url() == "https://www.reddit.com"

    oauth_auth = RedditAuth(http=http, auth_mode="app", client_id="id", client_secret="secret", refresh_token=None)
    oauth_client = RedditClient(http=http, auth=oauth_auth)
    assert oauth_client.base_url() == "https://oauth.reddit.com"
