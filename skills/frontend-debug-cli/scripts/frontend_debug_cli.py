#!/usr/bin/env python3
"""
Capture frontend debug artifacts (logs, HAR, trace, screenshots) using Playwright.
"""

from __future__ import annotations

import argparse
import json
import shlex
import shutil
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Tuple
from urllib.parse import urlparse


PlaywrightError = Exception
sync_playwright = None


SENSITIVE_HEADERS = {
    "authorization",
    "cookie",
    "proxy-authorization",
    "x-api-key",
    "x-auth-token",
}


@dataclass
class LimitedList:
    max_items: int
    items: List[Dict[str, Any]]
    truncated: bool = False

    def add(self, item: Dict[str, Any]) -> None:
        if self.max_items <= 0:
            return
        if len(self.items) < self.max_items:
            self.items.append(item)
            return
        if not self.truncated:
            self.items.append({"_truncated": True, "max_items": self.max_items})
            self.truncated = True


def utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def parse_viewport(value: str) -> Dict[str, int]:
    try:
        width_str, height_str = value.lower().split("x")
        width = int(width_str.strip())
        height = int(height_str.strip())
    except ValueError as exc:
        raise argparse.ArgumentTypeError("Viewport must be WIDTHxHEIGHT, e.g. 1280x720") from exc
    if width <= 0 or height <= 0:
        raise argparse.ArgumentTypeError("Viewport dimensions must be positive")
    return {"width": width, "height": height}


def parse_geolocation(value: str) -> Dict[str, float]:
    try:
        lat_str, lon_str = value.split(",")
        latitude = float(lat_str.strip())
        longitude = float(lon_str.strip())
    except ValueError as exc:
        raise argparse.ArgumentTypeError("Geolocation must be LAT,LON, e.g. 37.7749,-122.4194") from exc
    return {"latitude": latitude, "longitude": longitude}


def parse_headers(values: Iterable[str]) -> Dict[str, str]:
    headers: Dict[str, str] = {}
    for value in values:
        if ":" in value:
            key, val = value.split(":", 1)
        elif "=" in value:
            key, val = value.split("=", 1)
        else:
            raise argparse.ArgumentTypeError("Headers must be in 'Key: Value' or 'Key=Value' format")
        key = key.strip()
        val = val.strip()
        if not key:
            raise argparse.ArgumentTypeError("Header key cannot be empty")
        headers[key] = val
    return headers


def redact_headers(headers: Dict[str, str]) -> Dict[str, str]:
    redacted: Dict[str, str] = {}
    for key, value in headers.items():
        if key.lower() in SENSITIVE_HEADERS:
            redacted[key] = "***"
        else:
            redacted[key] = value
    return redacted


def ensure_output_dir(out_dir: Optional[str]) -> Path:
    if out_dir:
        path = Path(out_dir)
    else:
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        path = Path("artifacts") / "frontend-debug" / timestamp
    path.mkdir(parents=True, exist_ok=True)
    return path


def collect_performance(page) -> Dict[str, Any]:
    script = """
    () => {
      const nav = performance.getEntriesByType('navigation')[0] || null;
      const paintEntries = performance.getEntriesByType('paint') || [];
      const paints = {};
      for (const entry of paintEntries) {
        paints[entry.name] = entry.startTime;
      }
      const lcpEntries = performance.getEntriesByType('largest-contentful-paint') || [];
      const lcp = lcpEntries.length ? lcpEntries[lcpEntries.length - 1].startTime : null;
      return {
        navigation: nav ? {
          startTime: nav.startTime,
          duration: nav.duration,
          fetchStart: nav.fetchStart,
          requestStart: nav.requestStart,
          responseStart: nav.responseStart,
          responseEnd: nav.responseEnd,
          domContentLoadedEventEnd: nav.domContentLoadedEventEnd,
          loadEventEnd: nav.loadEventEnd,
          transferSize: nav.transferSize,
          encodedBodySize: nav.encodedBodySize,
          decodedBodySize: nav.decodedBodySize
        } : null,
        paints,
        lcp,
        now: performance.now(),
        readyState: document.readyState
      };
    }
    """
    try:
        return page.evaluate(script)
    except PlaywrightError:
        return {"error": "Failed to collect performance entries"}


def write_json(path: Path, data: Any) -> None:
    with path.open("w", encoding="utf-8") as handle:
        json.dump(data, handle, indent=2, sort_keys=True)


def run_lighthouse(url: str, out_dir: Path, headless: bool, extra_flags: Optional[str]) -> Dict[str, Any]:
    lighthouse = shutil.which("lighthouse")
    if not lighthouse:
        return {"status": "skipped", "reason": "lighthouse CLI not found in PATH"}

    output_path = out_dir / "lighthouse.json"
    cmd = [
        lighthouse,
        url,
        "--output",
        "json",
        "--output-path",
        str(output_path),
        "--quiet",
    ]
    chrome_flags = "--no-sandbox"
    if headless:
        chrome_flags = "--headless --no-sandbox"
    cmd.append(f"--chrome-flags={chrome_flags}")

    if extra_flags:
        cmd.extend(shlex.split(extra_flags))

    result = subprocess.run(cmd, capture_output=True, text=True, check=False)
    report: Dict[str, Any] = {
        "status": "ok" if result.returncode == 0 else "error",
        "exit_code": result.returncode,
        "output_path": str(output_path),
    }
    if result.returncode != 0:
        report["stderr"] = (result.stderr or "").strip()[:2000]
        report["stdout"] = (result.stdout or "").strip()[:2000]
        return report

    try:
        data = json.loads(output_path.read_text(encoding="utf-8"))
        categories = data.get("categories", {})
        report["scores"] = {
            name: category.get("score")
            for name, category in categories.items()
            if isinstance(category, dict)
        }
    except Exception as exc:  # pragma: no cover
        report["parse_error"] = f"{type(exc).__name__}: {exc}"
    return report


def list_devices() -> int:
    ensure_playwright()
    with sync_playwright() as p:
        for name in sorted(p.devices.keys()):
            print(name)
    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Capture frontend debug artifacts with Playwright.")
    parser.add_argument("--url", help="Target URL to debug")
    parser.add_argument("--out", dest="out_dir", help="Output directory (default: artifacts/frontend-debug/<ts>)")
    parser.add_argument(
        "--browser",
        choices=["chromium", "firefox", "webkit"],
        default="chromium",
        help="Browser engine",
    )
    parser.add_argument(
        "--headless",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="Run headless (default: true)",
    )
    parser.add_argument("--device", help="Playwright device name (use --list-devices)")
    parser.add_argument("--viewport", type=parse_viewport, help="Viewport size: WIDTHxHEIGHT")
    parser.add_argument("--user-agent", help="Custom user agent string")
    parser.add_argument("--locale", help="Locale, e.g. en-US")
    parser.add_argument("--timezone", help="Timezone ID, e.g. America/Los_Angeles")
    parser.add_argument("--geolocation", type=parse_geolocation, help="Geolocation: LAT,LON")
    parser.add_argument("--permissions", help="Comma-separated permissions, e.g. geolocation,notifications")
    parser.add_argument("--proxy", help="Proxy server, e.g. http://localhost:8080")
    parser.add_argument("--ignore-https-errors", action="store_true", help="Ignore HTTPS errors")
    parser.add_argument(
        "--extra-header",
        action="append",
        default=[],
        help="Extra header (repeatable) in 'Key: Value' format",
    )
    parser.add_argument("--storage-state-in", help="Storage state JSON to load")
    parser.add_argument("--save-storage-state", action="store_true", help="Save storage state after run")
    parser.add_argument("--storage-state-out", help="Storage state output path")
    parser.add_argument("--access-token", help="Access token to inject as a cookie for auth")
    parser.add_argument("--access-token-file", help="Read access token from file (trimmed)")
    parser.add_argument("--cookie-name", default="access_token", help="Auth cookie name (default: access_token)")
    parser.add_argument(
        "--wait-until",
        choices=["load", "domcontentloaded", "networkidle"],
        default="load",
        help="Wait condition for page.goto",
    )
    parser.add_argument("--timeout", type=int, default=45000, help="Navigation timeout (ms)")
    parser.add_argument("--wait-after", type=int, default=2000, help="Wait after load (ms)")
    parser.add_argument(
        "--wait-for-selector",
        action="append",
        default=[],
        help="Wait for selector to appear (repeatable)",
    )
    parser.add_argument(
        "--trace",
        action=argparse.BooleanOptionalAction,
        default=False,
        help="Record Playwright trace",
    )
    parser.add_argument(
        "--har",
        action=argparse.BooleanOptionalAction,
        default=False,
        help="Record HAR file",
    )
    parser.add_argument(
        "--har-content",
        choices=["omit", "attach", "embed"],
        default="omit",
        help="HAR content mode (default: omit)",
    )
    parser.add_argument(
        "--screenshot",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="Capture screenshot (default: true)",
    )
    parser.add_argument("--full-page", action="store_true", help="Full-page screenshot")
    parser.add_argument("--save-html", action="store_true", help="Save page HTML")
    parser.add_argument("--max-console-entries", type=int, default=500)
    parser.add_argument("--max-page-errors", type=int, default=200)
    parser.add_argument("--max-network-errors", type=int, default=200)
    parser.add_argument("--max-http-errors", type=int, default=200)
    parser.add_argument(
        "--lighthouse",
        action=argparse.BooleanOptionalAction,
        default=False,
        help="Run Lighthouse (requires lighthouse CLI)",
    )
    parser.add_argument("--lighthouse-flags", help="Extra Lighthouse flags")
    parser.add_argument("--list-devices", action="store_true", help="List Playwright device names")
    return parser.parse_args()


def load_access_token(args: argparse.Namespace) -> Tuple[Optional[str], Optional[str]]:
    if args.access_token and args.access_token_file:
        raise SystemExit("Use either --access-token or --access-token-file, not both.")
    if args.access_token_file:
        token_path = Path(args.access_token_file)
        token = token_path.read_text(encoding="utf-8").strip()
        return token, "file"
    if args.access_token:
        return args.access_token.strip(), "inline"
    return None, None


def build_cookie(url: str, name: str, value: str) -> Dict[str, Any]:
    parsed = urlparse(url)
    if not parsed.scheme or not parsed.netloc:
        raise SystemExit("Invalid --url. Expected full URL with scheme and host.")
    base_url = f"{parsed.scheme}://{parsed.netloc}"
    return {
        "name": name,
        "value": value,
        "url": base_url,
        "httpOnly": False,
        "secure": parsed.scheme == "https",
        "sameSite": "Lax",
    }


def ensure_playwright() -> None:
    global PlaywrightError, sync_playwright
    if sync_playwright is not None:
        return
    try:
        from playwright.sync_api import Error as playwright_error
        from playwright.sync_api import sync_playwright as playwright_sync
    except Exception as exc:  # pragma: no cover
        print(
            "Playwright is not available. Install with:\n"
            "  pip install playwright\n"
            "  playwright install\n",
            file=sys.stderr,
        )
        raise SystemExit(2) from exc
    PlaywrightError = playwright_error
    sync_playwright = playwright_sync


def main() -> int:
    args = parse_args()
    if args.list_devices:
        return list_devices()
    if not args.url:
        raise SystemExit("Missing --url. Use --list-devices to inspect available devices.")

    ensure_playwright()

    out_dir = ensure_output_dir(args.out_dir)
    start_time = utc_now()

    extra_headers = parse_headers(args.extra_header) if args.extra_header else {}
    access_token, access_token_source = load_access_token(args)
    if access_token == "":
        access_token = None
    summary: Dict[str, Any] = {
        "url": args.url,
        "started_at": start_time,
        "browser": args.browser,
        "headless": args.headless,
        "device": args.device,
        "viewport": args.viewport,
        "wait_until": args.wait_until,
        "timeout_ms": args.timeout,
        "wait_after_ms": args.wait_after,
        "extra_headers": redact_headers(extra_headers),
        "artifacts": {},
        "counts": {},
    }
    summary["auth"] = {
        "token_provided": bool(access_token),
        "token_source": access_token_source,
        "cookie_name": args.cookie_name if access_token else None,
    }

    console_logs = LimitedList(args.max_console_entries, [])
    page_errors = LimitedList(args.max_page_errors, [])
    request_failures = LimitedList(args.max_network_errors, [])
    http_errors = LimitedList(args.max_http_errors, [])
    counts = {
        "console_total": 0,
        "console_errors": 0,
        "page_errors": 0,
        "request_failures": 0,
        "http_errors": 0,
    }

    nav_response = None
    nav_error: Optional[str] = None
    performance_data: Dict[str, Any] = {}
    page_title: Optional[str] = None
    final_url: Optional[str] = None

    try:
        with sync_playwright() as p:
            if args.device and args.device not in p.devices:
                available = ", ".join(sorted(p.devices.keys()))
                raise SystemExit(f"Unknown device '{args.device}'. Available devices: {available}")

            launch_args: Dict[str, Any] = {"headless": args.headless}
            if args.proxy:
                launch_args["proxy"] = {"server": args.proxy}

            browser_type = getattr(p, args.browser)
            browser = browser_type.launch(**launch_args)

            context_args: Dict[str, Any] = {"ignore_https_errors": args.ignore_https_errors}
            if args.device:
                context_args.update(p.devices[args.device])
            if args.viewport:
                context_args["viewport"] = args.viewport
            if args.user_agent:
                context_args["user_agent"] = args.user_agent
            if args.locale:
                context_args["locale"] = args.locale
            if args.timezone:
                context_args["timezone_id"] = args.timezone
            if args.geolocation:
                context_args["geolocation"] = args.geolocation
            if args.permissions:
                context_args["permissions"] = [item.strip() for item in args.permissions.split(",") if item.strip()]
            if extra_headers:
                context_args["extra_http_headers"] = extra_headers
            if args.storage_state_in:
                context_args["storage_state"] = args.storage_state_in
            if args.har:
                context_args["record_har_path"] = str(out_dir / "network.har")
                context_args["record_har_content"] = args.har_content

            context = browser.new_context(**context_args)
            if access_token:
                context.add_cookies([build_cookie(args.url, args.cookie_name, access_token)])
            page = context.new_page()

            def on_console(msg) -> None:
                counts["console_total"] += 1
                if msg.type == "error":
                    counts["console_errors"] += 1
                console_logs.add(
                    {
                        "type": msg.type,
                        "text": msg.text,
                        "location": msg.location,
                    }
                )

            def on_page_error(err) -> None:
                counts["page_errors"] += 1
                page_errors.add({"message": str(err)})

            def on_request_failed(request) -> None:
                try:
                    counts["request_failures"] += 1
                    failure = request.failure
                    failure_text = None
                    if failure:
                        if isinstance(failure, str):
                            failure_text = failure
                        elif isinstance(failure, dict):
                            failure_text = failure.get("errorText") or failure.get("error_text")
                        else:
                            failure_text = getattr(failure, "error_text", str(failure))
                    request_failures.add(
                        {
                            "url": request.url,
                            "method": request.method,
                            "resource_type": request.resource_type,
                            "failure": failure_text,
                        }
                    )
                except Exception as exc:
                    page_errors.add({"message": f"request_failed handler error: {exc}"})

            def on_response(response) -> None:
                if response.status >= 400:
                    counts["http_errors"] += 1
                    http_errors.add(
                        {
                            "url": response.url,
                            "status": response.status,
                            "status_text": response.status_text,
                            "method": response.request.method if response.request else None,
                            "resource_type": response.request.resource_type if response.request else None,
                        }
                    )

            page.on("console", on_console)
            page.on("pageerror", on_page_error)
            page.on("requestfailed", on_request_failed)
            page.on("response", on_response)

            if args.trace:
                context.tracing.start(screenshots=True, snapshots=True, sources=True)

            try:
                nav_response = page.goto(args.url, wait_until=args.wait_until, timeout=args.timeout)
            except PlaywrightError as exc:
                nav_error = f"{type(exc).__name__}: {exc}"

            final_url = page.url

            for selector in args.wait_for_selector:
                try:
                    page.wait_for_selector(selector, timeout=args.timeout)
                except PlaywrightError as exc:
                    page_errors.add({"message": f"wait_for_selector failed: {selector}", "error": str(exc)})

            if args.wait_after > 0:
                page.wait_for_timeout(args.wait_after)

            try:
                page_title = page.title()
            except PlaywrightError:
                page_title = None

            performance_data = collect_performance(page)

            if args.screenshot:
                screenshot_path = out_dir / "screenshot.png"
                page.screenshot(path=str(screenshot_path), full_page=args.full_page)
                summary["artifacts"]["screenshot"] = str(screenshot_path)

            if args.save_html:
                html_path = out_dir / "page.html"
                html_path.write_text(page.content(), encoding="utf-8")
                summary["artifacts"]["page_html"] = str(html_path)

            if args.save_storage_state:
                storage_path = Path(args.storage_state_out) if args.storage_state_out else out_dir / "storage_state.json"
                context.storage_state(path=str(storage_path))
                summary["artifacts"]["storage_state"] = str(storage_path)

            if args.trace:
                trace_path = out_dir / "trace.zip"
                context.tracing.stop(path=str(trace_path))
                summary["artifacts"]["trace"] = str(trace_path)

            context.close()
            browser.close()

    except SystemExit:
        raise
    except Exception as exc:
        summary["error"] = f"{type(exc).__name__}: {exc}"
    finally:
        summary["finished_at"] = utc_now()
        summary["final_url"] = final_url
        summary["title"] = page_title
        if nav_response is not None:
            summary["final_url"] = nav_response.url
            summary["status"] = nav_response.status
        if nav_error:
            summary["navigation_error"] = nav_error
        summary["counts"] = counts
        if performance_data:
            summary["artifacts"]["performance"] = str(out_dir / "performance.json")
            write_json(out_dir / "performance.json", performance_data)
        summary["artifacts"]["console"] = str(out_dir / "console.json")
        summary["artifacts"]["page_errors"] = str(out_dir / "page_errors.json")
        summary["artifacts"]["network_failures"] = str(out_dir / "network_failures.json")
        summary["artifacts"]["http_errors"] = str(out_dir / "http_errors.json")
        write_json(out_dir / "console.json", console_logs.items)
        write_json(out_dir / "page_errors.json", page_errors.items)
        write_json(out_dir / "network_failures.json", request_failures.items)
        write_json(out_dir / "http_errors.json", http_errors.items)

    if args.har:
        summary["artifacts"]["har"] = str(out_dir / "network.har")

    if args.lighthouse:
        summary["lighthouse"] = run_lighthouse(args.url, out_dir, args.headless, args.lighthouse_flags)

    summary_path = out_dir / "summary.json"
    write_json(summary_path, summary)

    print(f"Frontend debug bundle saved to: {out_dir}")
    print(f"Summary: {summary_path}")
    if summary.get("error"):
        print(f"Error: {summary['error']}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
