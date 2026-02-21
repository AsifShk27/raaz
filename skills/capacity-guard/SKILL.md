---
name: capacity-guard
description: Calculate safe worker concurrency for trading-platform install/rebuild operations using host load, memory, container count, and Kubernetes pressure signals.
---

# Capacity Guard

Use this skill before high-parallel install/redeploy/rebuild runs.

## Command

```bash
bash scripts/capacity-guard.sh
```

JSON output:

```bash
bash scripts/capacity-guard.sh --json
```

## Output

- host CPU/load/memory signals
- container and pod pressure indicators
- recommended `max-workers` for `tpdeploy install` / `tpdeploy rebuild-all`

## Notes

This is advisory and intentionally conservative for shared runtime stability.
