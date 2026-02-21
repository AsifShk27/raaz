---
name: frontend-debug-cli
description: Collect browser diagnostics and artifacts (console errors, network failures, HAR, trace, screenshots, HTML, storage state) for frontend debugging and bug reproduction. Use when investigating broken UI flows, failed network calls, console exceptions, rendering issues, auth/session problems, or when a shareable debug bundle is needed for a URL or frontend regression.
---

# Frontend Debug CLI

## Overview

Use this skill to run a Playwright-based CLI that captures a reproducible frontend debug bundle from a web page.

## Quick Start

1. Capture a baseline bundle:

```bash
python scripts/frontend_debug_cli.py --url https://example.com
```

2. Inspect `summary.json`, `console.json`, and `network_failures.json`.

3. For deep analysis, rerun with trace and HAR:

```bash
python scripts/frontend_debug_cli.py --url https://example.com --trace --har --save-html
```

Open a trace with:

```bash
npx playwright show-trace <output-dir>/trace.zip
```

## Workflow

1. Decide the capture depth.
2. Reproduce the issue with waits or selectors.
3. Review artifacts and summarize findings.

## CLI Usage

Command:

```bash
python scripts/frontend_debug_cli.py --url <url> [options]
```

Key options:

- `--out <dir>` Set output directory (default: `artifacts/frontend-debug/<timestamp>`).
- `--trace` Record a Playwright trace (`trace.zip`).
- `--har` Record a HAR file (`network.har`).
- `--har-content <omit|attach|embed>` Control HAR payload size.
- `--screenshot/--no-screenshot` Enable or disable screenshots.
- `--full-page` Capture full-page screenshots.
- `--save-html` Save rendered HTML to `page.html`.
- `--wait-for-selector <css>` Wait for a selector (repeatable).
- `--wait-after <ms>` Extra wait after load to allow client JS.
- `--device <name>` Emulate a device (use `--list-devices`).
- `--storage-state-in <path>` Load auth/session state.
- `--save-storage-state` Save storage state after run.
- `--access-token <token>` Inject auth cookie (default name `access_token`).
- `--access-token-file <path>` Read auth token from file and inject cookie.
- `--cookie-name <name>` Override auth cookie name.
- `--ignore-https-errors` Ignore invalid TLS certs (local/dev).
- `--lighthouse` Run Lighthouse if installed (saves `lighthouse.json`).

Examples:

Capture a logged-in flow using storage state:

```bash
python scripts/frontend_debug_cli.py \
  --url https://example.com/app \
  --storage-state-in /path/to/state.json \
  --trace --har --wait-after 3000
```

Emulate a device:

```bash
python scripts/frontend_debug_cli.py --url https://example.com --device "iPhone 14"
```

Inject a token as a cookie:

```bash
python scripts/frontend_debug_cli.py \
  --url http://localhost:30000/scanner \
  --access-token-file /tmp/access_token.txt \
  --trace --har --wait-after 2000
```

## Outputs

- `summary.json` Top-level summary and artifact paths.
- `console.json` Console logs (limited to max entries).
- `page_errors.json` Unhandled exceptions.
- `network_failures.json` Failed requests.
- `http_errors.json` Responses with status >= 400.
- `performance.json` Navigation and paint timing data.
- `screenshot.png` Screenshot (if enabled).
- `trace.zip` Playwright trace (if enabled).
- `network.har` HAR file (if enabled).
- `page.html` Rendered HTML (if enabled).
- `storage_state.json` Storage state (if enabled).
- `lighthouse.json` Lighthouse report (if enabled).

## Prereqs

- Install Playwright: `pip install playwright` then `playwright install`.
- Install Lighthouse CLI if using `--lighthouse`.

## Tips

- Use `--wait-for-selector` for pages with async bootstrapping.
- Use `--ignore-https-errors` for local TLS certs.
- Prefer `--trace` when debugging race conditions or flaky UI flows.
