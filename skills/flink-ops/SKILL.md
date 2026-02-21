---
name: flink-ops
description: Operate FlinkDeployments in the trading platform (status, logs, suspend/resume, restart nonce, savepoint trigger) with explicit mutation safeguards.
---

# Flink Ops

Use this skill for Flink runtime health and controlled operational actions.

## Examples

Status overview:

```bash
bash scripts/flink-ops.sh status --namespace streaming
```

Logs for one job:

```bash
bash scripts/flink-ops.sh logs --namespace streaming --job ict-event-tagger --tail 300
```

Controlled restart/savepoint actions:

```bash
bash scripts/flink-ops.sh restart --namespace streaming --job ict-event-tagger --yes
bash scripts/flink-ops.sh savepoint --namespace streaming --job ict-event-tagger --yes
```

Suspend/resume:

```bash
bash scripts/flink-ops.sh suspend --namespace streaming --job ict-event-tagger --yes
bash scripts/flink-ops.sh resume --namespace streaming --job ict-event-tagger --yes
```

## Safety

Mutating commands require `--yes`.
Script performs Kubernetes API reachability preflight before command execution.
