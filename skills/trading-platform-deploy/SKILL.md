---
name: trading-platform-deploy
description: Build, push, and deploy trading-platform services via the tpdeploy CLI (no MCP).
---

# Trading Platform Deploy Skill

CLI-only enforcement:
- Use `tpdeploy` first when this skill is available.
- Do NOT use MCP for deployments.
- Git mutation safety is enforced in `tpdeploy` by default.
- For full installs/redeploys, use `tpdeploy install ...`; only use the raw script path if `tpdeploy` is unavailable.
- Never use `pwsh` in this environment unless explicitly confirmed installed.

A CLI tool for building, pushing, and deploying services in the trading platform.

Use this skill when the user says **install the trading platform**, **redeploy**, **reinstall**, or **run the install script** for the platform.

Rebuild flow for a service:
1. Update Helm image refs (values.yaml and subchart values).
2. `docker build` directly from the service Dockerfile.
3. Push to Zot (`localhost:30500`).
4. Delete the deployment (or FlinkDeployment).
5. `helm dependency update` for the chart.
6. `helm upgrade --install` the chart.

Registry preflight behavior:
- `tpdeploy push`, `tpdeploy rebuild`, and `tpdeploy rebuild-all` now auto-ensure local Zot is up/waiting when target registry is `localhost:30500`.
- If `scripts/ci/local_zot_stack.sh` is missing or Zot cannot become healthy, push paths fail fast with an explicit registry-preflight error.

## Installation

The `tpdeploy` CLI is a standalone Python script located at `scripts/tpdeploy.py`.

### Requirements
- Python 3.8+
- PyYAML (`pip install pyyaml`)
- Docker
- Helm
- kubectl
- Kind (for local Kubernetes cluster)

## Usage

```bash
# Get service info
tpdeploy info <service> [--chart <chart>]

# Build Docker image
tpdeploy build <service> [--chart <chart>]

# Push to Zot registry
tpdeploy push <service> [--chart <chart>]

# Delete deployment
tpdeploy delete <service> [--chart <chart>]

# Run helm upgrade (includes `helm dependency update`)
tpdeploy upgrade [--chart <chart>]

# Full rebuild (update helm refs + build + push + delete + dependency update + upgrade)
tpdeploy rebuild <service> [--chart <chart>]

# Rebuild multiple services in parallel (single dependency update + upgrade)
tpdeploy rebuild-all <service1> <service2> ... [--chart <chart>] [--max-workers <n>]

# Full install/redeploy (preferred)
tpdeploy install [--max-workers <n>] [--skip-images] [--skip-metrics-server] [--skip-helm] [--cleanup-cluster] [--infra-only|--data-only|--apps-only|--monitoring-only]

# Explicit exception for mutating git commands (requires user permission ticket)
tpdeploy --allow-mutating-git --git-permission-ticket "<ticket-id>" <command> ...
```

## Git Safety Guardrail

- `tpdeploy` blocks mutating Git commands by default.
- Read-only Git commands are allowed.
- To permit a specific user-approved exception, pass both:
  - `--allow-mutating-git`
  - `--git-permission-ticket "<ticket-id>"`
- Environment variable equivalents:
  - `TPDEPLOY_ALLOW_MUTATING_GIT=true`
  - `TPDEPLOY_GIT_PERMISSION_TICKET=<ticket-id>`

## Full Install / Redeploy (platform_installation)

Run full stack install/redeploy through `tpdeploy install` so execution stays CLI/skill-first.

Preferred:

```bash
tpdeploy install --max-workers 3 --no-confirm
```

Common install flags:
- `--skip-images` when you don’t need to rebuild images
- `--skip-metrics-server` only if metrics API is intentionally managed elsewhere
- `--skip-helm` to only build images
- `--cleanup-cluster` if Helm secrets are stuck/corrupt
- `--infra-only` / `--data-only` / `--apps-only` / `--monitoring-only` for partial redeploys

Direct script fallback (only if `tpdeploy` is unavailable):

```powershell
Set-Location D:\projects\trading-platform
.\scripts\Install-TradingPlatform-Python.ps1 -Force -MaxWorkers 3 -NoConfirm
```

Fallback (direct Python installer):

```powershell
Set-Location D:\projects\trading-platform
if (-not (Test-Path .venv)) { python -m venv .venv }
.\.venv\Scripts\Activate.ps1
pip install -r platform_installation\requirements.txt
python -m platform_installation.main --force
```

From WSL (calls PowerShell; non-interactive safe):

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File D:\\projects\\trading-platform\\scripts\\Install-TradingPlatform-Python.ps1 -Force -MaxWorkers 3 -NoConfirm
```

Validation:

```bash
kubectl get pods -A
kubectl -n trading get events --sort-by=.lastTimestamp
```

## Charts and Namespaces

| Chart | Namespace |
|-------|-----------|
| trading-platform-apps | trading-platform-apps |
| trading-platform-data | data-services |
| trading-platform-infra | streaming |
| trading-platform-monitoring | monitoring |

## Flink Jobs (trading-platform-infra chart)

The following Flink jobs are in `ict-flink-jobs` subchart:

| Job Name | Repository | Description |
|----------|------------|-------------|
| `ict-confluence-aggregator` | ict-confluence-aggregator | ICT confluence aggregation |
| `ict-event-tagger` | ict-event-tagger-java | ICT event tagging |
| `ict-lifecycle-tracker` | ict-lifecycle-tracker-java | ICT lifecycle tracking |
| `ohlcv-aggregation` | ohlcv-aggregation | OHLCV bar aggregation |
| `portfolio-pnl` | portfolio-pnl | Portfolio P&L calculation |
| `raw-tick-storage` | raw-tick-storage | Raw tick data storage |
| `bars-storage` | bars-storage | Aggregated bars storage |
| `ict-confluence-stream` | ict-confluence-stream | ICT confluence streaming |
| `technical-indicators` | technical-indicators-java | Technical indicators calculation |

## Examples

```bash
# Get info about a Flink job (base name or -java/-sql)
tpdeploy info technical-indicators --chart trading-platform-infra
tpdeploy info technical-indicators-java --chart trading-platform-infra

# Rebuild a Flink job
tpdeploy rebuild ict-event-tagger --chart trading-platform-infra
tpdeploy rebuild ict-event-tagger-java --chart trading-platform-infra

# Get info about an app service
tpdeploy info order-router --chart trading-platform-apps

# Rebuild order-router
tpdeploy rebuild order-router --chart trading-platform-apps

# Rebuild multiple services in parallel
tpdeploy rebuild-all order-router dhan-adapter --chart trading-platform-apps

# Run helm upgrade for a chart
tpdeploy upgrade --chart trading-platform-apps
```

## Configuration

- **Trading Platform Root**: `/mnt/d/projects/trading-platform/`
- **Registry**: `localhost:30500` (Zot)
- **Helm Charts Directory**: `helm-deployments/`

## Service Directory Mapping

For Flink jobs, the service name in `values.yaml` may differ from the directory name:

| values.yaml name | Directory |
|------------------|-----------|
| `technical-indicators` | `services/flink-jobs/technical-indicators-java` |
| `ict-event-tagger` | `services/flink-jobs/ict-event-tagger-java` |
| `ict-lifecycle-tracker` | `services/flink-jobs/ict-lifecycle-tracker-java` |
| `raw-tick-storage` | `services/flink-jobs/raw-tick-storage-java` |
