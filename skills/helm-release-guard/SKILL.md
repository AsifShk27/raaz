---
name: helm-release-guard
description: Run pre-upgrade Helm safety gates (lint, template, diff, mutable image-tag checks) and fail fast before risky releases.
---

# Helm Release Guard

Use this skill before `helm upgrade` or `tpdeploy upgrade` when you need a deterministic safety report.

## Command

```bash
bash scripts/helm-release-guard.sh \
  --release trading-platform-infra \
  --chart /mnt/d/Projects/trading-platform/helm-deployments/trading-platform-infra \
  --namespace streaming \
  --values /mnt/d/Projects/trading-platform/helm-deployments/trading-platform-infra/values.yaml
```

## Behavior

The guard runs:
- `helm lint`
- `helm template`
- `helm diff upgrade --allow-unreleased`
- mutable tag scan (`latest`, `main`, `master`) against rendered manifests

Artifacts are written under `artifacts/helm-release-guard-*` including `summary.md`.

## Notes

- Requires Helm plugin `diff`.
- Fails by default if mutable image tags are detected.
- Use `--allow-mutable-tags` only for explicit exceptions.
