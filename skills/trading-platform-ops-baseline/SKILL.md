---
name: trading-platform-ops-baseline
description: Install and verify the trading-platform operational CLI baseline for Raaz and collab workers (tpdeploy/agentctl/trpg/kubectl/helm/docker/yq/stern/k9s/kubectx/kubens/kcat/helm-diff) with deterministic health checks.
---

# Trading Platform Ops Baseline

Use this skill when you need to:
- bootstrap a new Raaz/collab host for trading-platform operations,
- verify required CLIs and critical plugin/variant constraints,
- repair drift (missing tools, wrong `yq` flavor, missing `helm diff`).

## Why This Skill Exists

The trading-platform runtime relies on a stable CLI contract:
- deploy/install should run via `tpdeploy` (skill-first),
- runtime orchestration should run via `agentctl`/`trpg`,
- Kubernetes/Helm operations require consistent tool behavior across workers.

## Commands

Run installer (idempotent):

```bash
bash scripts/baseline-install.sh
```

Run doctor check:

```bash
bash scripts/baseline-doctor.sh
```

Strict mode (fail if optional tools are missing too):

```bash
bash scripts/baseline-doctor.sh --strict-optional
```

## Notes

- Installer only writes to user space (`$HOME/.local/bin`, Helm user plugin dir).
- `kcat` is provided via a Docker-backed wrapper when a native binary is unavailable.
- `yq` is enforced to `mikefarah/yq` v4 behavior because Python `yq` breaks parts of the Strimzi pipeline.
