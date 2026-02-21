from __future__ import annotations

import base64
import gzip
import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request
from typing import Dict, List, Optional

try:
    import requests
except Exception:  # pragma: no cover - fallback path for minimal environments.
    requests = None


DEFAULT_USER_AGENT = os.environ.get(
    "REDDIT_USER_AGENT",
    "raaz-reddit-cli/2.0 (contact: raaz@local)",
)

RETRYABLE_STATUS = {429, 500, 502, 503, 504}
VALID_AUTH_MODES = {"auto", "public", "app", "refresh"}


def _retry_delay(retry_after: Optional[str], attempt: int) -> float:
    if retry_after:
        try:
            return max(1.0, float(retry_after))
        except ValueError:
            pass
    return min(30.0, 1.5 ** attempt)


def _compact_error_body(body: str, limit: int = 160) -> str:
    text = " ".join(body.split())
    if not text:
        return "no response body"
    if len(text) <= limit:
        return text
    return text[: max(0, limit - 3)] + "..."


class HttpClient:
    def __init__(self, user_agent: str, timeout: int, max_retries: int, sleep_ms: int = 0) -> None:
        self.user_agent = user_agent
        self.timeout = timeout
        self.max_retries = max_retries
        self.sleep_ms = sleep_ms

    def request_json(
        self,
        method: str,
        url: str,
        headers: Optional[Dict[str, str]] = None,
        data: Optional[bytes] = None,
    ) -> dict:
        req_headers = {
            "User-Agent": self.user_agent,
            "Accept": "application/json",
        }
        if headers:
            req_headers.update(headers)

        if requests is not None:
            return self._request_json_requests(method, url, req_headers, data)
        return self._request_json_urllib(method, url, req_headers, data)

    def _request_json_requests(
        self,
        method: str,
        url: str,
        headers: Dict[str, str],
        data: Optional[bytes],
    ) -> dict:
        last_error: Optional[Exception] = None
        for attempt in range(1, self.max_retries + 1):
            try:
                response = requests.request(method=method, url=url, headers=headers, data=data, timeout=self.timeout)
            except requests.RequestException as exc:
                time.sleep(_retry_delay(None, attempt))
                last_error = exc
                continue

            if response.status_code in RETRYABLE_STATUS:
                time.sleep(_retry_delay(response.headers.get("Retry-After"), attempt))
                last_error = RuntimeError(f"HTTP {response.status_code} for {url}")
                continue
            if response.status_code >= 400:
                raise RuntimeError(
                    f"HTTP {response.status_code} for {url}: {_compact_error_body(response.text)}"
                )

            try:
                return response.json()
            except ValueError as exc:
                raise RuntimeError(f"Invalid JSON response for {url}: {_compact_error_body(response.text)}") from exc

        raise RuntimeError(f"Failed request after {self.max_retries} attempts: {url}") from last_error

    def _request_json_urllib(
        self,
        method: str,
        url: str,
        headers: Dict[str, str],
        data: Optional[bytes],
    ) -> dict:
        last_error: Optional[Exception] = None
        for attempt in range(1, self.max_retries + 1):
            request = urllib.request.Request(url, headers=headers, method=method, data=data)
            try:
                with urllib.request.urlopen(request, timeout=self.timeout) as response:
                    payload = response.read()
                    if response.headers.get("Content-Encoding") == "gzip":
                        payload = gzip.decompress(payload)
                    return json.loads(payload.decode("utf-8"))
            except urllib.error.HTTPError as exc:
                if exc.code in RETRYABLE_STATUS:
                    time.sleep(_retry_delay(exc.headers.get("Retry-After"), attempt))
                    last_error = exc
                    continue
                body = exc.read().decode("utf-8", errors="ignore") if exc.fp else ""
                raise RuntimeError(f"HTTP {exc.code} for {url}: {_compact_error_body(body)}") from exc
            except urllib.error.URLError as exc:
                time.sleep(_retry_delay(None, attempt))
                last_error = exc
                continue

        raise RuntimeError(f"Failed request after {self.max_retries} attempts: {url}") from last_error

    def sleep_between_requests(self) -> None:
        if self.sleep_ms > 0:
            time.sleep(self.sleep_ms / 1000.0)


class RedditAuth:
    def __init__(
        self,
        http: HttpClient,
        auth_mode: str,
        client_id: Optional[str],
        client_secret: Optional[str],
        refresh_token: Optional[str],
    ) -> None:
        if auth_mode not in VALID_AUTH_MODES:
            raise RuntimeError(f"Unsupported auth mode: {auth_mode}")
        self.http = http
        self.auth_mode = auth_mode
        self.client_id = client_id
        self.client_secret = client_secret
        self.refresh_token = refresh_token
        self.access_token: Optional[str] = None
        self.expires_at: float = 0.0

    def effective_mode(self) -> str:
        if self.auth_mode != "auto":
            return self.auth_mode
        if self.client_id and self.client_secret:
            if self.refresh_token:
                return "refresh"
            return "app"
        return "public"

    def enabled(self) -> bool:
        return self.effective_mode() in {"app", "refresh"}

    def ensure_token(self) -> None:
        if not self.enabled():
            return
        if time.time() < self.expires_at - 60:
            return
        self._fetch_token()

    def auth_headers(self) -> Dict[str, str]:
        if not self.access_token:
            return {}
        return {"Authorization": f"bearer {self.access_token}"}

    def _fetch_token(self) -> None:
        mode = self.effective_mode()
        if not self.client_id or not self.client_secret:
            raise RuntimeError("Missing REDDIT_CLIENT_ID or REDDIT_CLIENT_SECRET for OAuth")
        if mode == "refresh" and not self.refresh_token:
            raise RuntimeError("Missing REDDIT_REFRESH_TOKEN for refresh-token OAuth")

        auth_raw = f"{self.client_id}:{self.client_secret}".encode("utf-8")
        auth_header = base64.b64encode(auth_raw).decode("ascii")
        headers = {
            "Authorization": f"Basic {auth_header}",
            "Content-Type": "application/x-www-form-urlencoded",
        }
        data = {
            "grant_type": "client_credentials" if mode == "app" else "refresh_token",
        }
        if mode == "refresh":
            data["refresh_token"] = self.refresh_token
        payload = urllib.parse.urlencode(data).encode("utf-8")
        token_data = self.http.request_json(
            "POST",
            "https://www.reddit.com/api/v1/access_token",
            headers=headers,
            data=payload,
        )
        token = token_data.get("access_token")
        if not token:
            raise RuntimeError(f"OAuth token response missing access_token: {token_data}")
        expires_in = int(token_data.get("expires_in", 3600))
        self.access_token = token
        self.expires_at = time.time() + expires_in


class RedditClient:
    def __init__(self, http: HttpClient, auth: RedditAuth) -> None:
        self.http = http
        self.auth = auth

    def base_url(self) -> str:
        if self.auth.enabled():
            return "https://oauth.reddit.com"
        return "https://www.reddit.com"

    def get_json(self, path: str, params: Optional[Dict[str, str]] = None) -> dict:
        self.auth.ensure_token()
        if not path.startswith("/"):
            path = "/" + path
        url = self.base_url() + path
        if params:
            url += "?" + urllib.parse.urlencode(params)
        headers = self.auth.auth_headers() if self.auth.enabled() else None
        payload = self.http.request_json("GET", url, headers=headers)
        self.http.sleep_between_requests()
        return payload


def fetch_posts(
    client: RedditClient,
    subreddit: str,
    sort: str,
    time_filter: str,
    limit: int,
) -> List[dict]:
    posts: List[dict] = []
    after: Optional[str] = None
    while len(posts) < limit:
        batch = min(100, limit - len(posts))
        params: Dict[str, str] = {"limit": str(batch)}
        if after:
            params["after"] = after
        if sort == "top" and time_filter:
            params["t"] = time_filter
        payload = client.get_json(f"/r/{subreddit}/{sort}.json", params)
        data = payload.get("data", {})
        for child in data.get("children", []):
            if child.get("kind") == "t3":
                post = child.get("data", {})
                if isinstance(post, dict):
                    posts.append(post)
        after = data.get("after")
        if not after:
            break
    return posts


def fetch_subreddits(client: RedditClient, where: str, limit: int) -> List[str]:
    subreddits: List[str] = []
    after: Optional[str] = None
    while len(subreddits) < limit:
        batch = min(100, limit - len(subreddits))
        params: Dict[str, str] = {"limit": str(batch)}
        if after:
            params["after"] = after
        payload = client.get_json(f"/subreddits/{where}.json", params)
        data = payload.get("data", {})
        for child in data.get("children", []):
            if child.get("kind") != "t5":
                continue
            name = child.get("data", {}).get("display_name")
            if name:
                subreddits.append(name)
        after = data.get("after")
        if not after:
            break
    return subreddits
