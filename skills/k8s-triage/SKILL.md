---
name: k8s-triage
description: Collect a deterministic Kubernetes incident bundle (context, pods, events, failing pod describe/logs, rollout status) for trading-platform triage and handoff.
---

# K8s Triage

Use this skill when pods are failing, rollouts are stuck, or you need a shareable triage bundle.

## Commands

Default (all namespaces):

```bash
bash scripts/k8s-triage.sh
```

Namespace-focused triage:

```bash
bash scripts/k8s-triage.sh --namespace streaming --output artifacts/k8s-triage-streaming
```

Narrow to workload label:

```bash
bash scripts/k8s-triage.sh --namespace streaming --selector app.kubernetes.io/name=ict-event-tagger
```

Skip log capture for fast metadata-only triage:

```bash
bash scripts/k8s-triage.sh --no-logs
```

Metrics API / HPA telemetry check (and optional self-heal):

```bash
bash scripts/k8s-metrics.sh --check-only
bash scripts/k8s-metrics.sh --ensure-metrics-server --namespace streaming --namespace data-services
```

## Output

The bundle includes:
- cluster context snapshots,
- pods/events snapshots,
- failing pod list,
- per-pod describe + logs,
- rollout status files (namespace mode),
- `summary.md`.

## Safety

- Script performs Kubernetes API reachability preflight and fails fast with actionable context/server guidance when kube context is stale or cluster is down.
