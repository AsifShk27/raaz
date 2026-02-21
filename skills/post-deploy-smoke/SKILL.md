---
name: post-deploy-smoke
description: Run post-deploy smoke checks across trading-platform namespaces (rollout status, failing pods, events, optional HTTP probes) with strict pass/fail output.
---

# Post Deploy Smoke

Use this skill after install/redeploy/rebuild operations.

## Command

```bash
bash scripts/post-deploy-smoke.sh \
  --namespace streaming \
  --namespace data-services \
  --namespace trading-platform-apps \
  --probe scanner=http://localhost:30000/health \
  --probe auth=http://localhost:30001/actuator/health
```

## Behavior

- Captures pods and events per namespace.
- Checks rollout status for all deployments and statefulsets.
- Flags unstable/failing pods (phase/reason/ready state).
- Optionally runs HTTP probes.
- Produces `summary.md` in `artifacts/post-deploy-smoke-*`.

## Notes

- Default namespaces: `streaming`, `data-services`, `trading-platform-apps`, `monitoring`.
- Use `--non-strict` only for exploratory checks.
- Script performs Kubernetes API reachability preflight before smoke execution.
