---
name: kafka-strimzi-ops
description: Operate Strimzi/Kafka resources for trading-platform (health/status, topic/user inspection, guarded topic create/delete) using Kubernetes CRDs.
---

# Kafka Strimzi Ops

Use this skill for Kafka health triage and controlled topic operations in Strimzi-managed clusters.

## Examples

Health snapshot:

```bash
bash scripts/kafka-strimzi-ops.sh status --namespace streaming
```

List topics/users:

```bash
bash scripts/kafka-strimzi-ops.sh topics --namespace streaming
bash scripts/kafka-strimzi-ops.sh users --namespace streaming
```

Describe/create/delete topic:

```bash
bash scripts/kafka-strimzi-ops.sh describe-topic --namespace streaming --topic ticks.raw
bash scripts/kafka-strimzi-ops.sh create-topic --namespace streaming --topic ticks.raw --partitions 12 --replicas 3 --yes
bash scripts/kafka-strimzi-ops.sh delete-topic --namespace streaming --topic ticks.raw --yes
```

## Safety

Mutating topic commands require `--yes`.
Script performs Kubernetes API reachability preflight before command execution.
