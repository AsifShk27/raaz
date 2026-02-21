# Trading Platform CLI Baseline Matrix

## Required (automation-safe)

- `tpdeploy`
- `agentctl`
- `trpg`
- `kubectl`
- `helm`
- `kind`
- `docker`
- `jq`
- `yq` (mikefarah v4)
- `rg`
- `stern`
- Helm plugin: `diff`

## Optional (operator convenience)

- `k9s`
- `kubectx`
- `kubens`
- `kcat`

## Policy Notes

- Deploy/install should be skill-first via `tpdeploy`.
- Runtime control should route through `agentctl`/`trpg` in persistent tmux-pane workflows.
- Direct script execution and ad-hoc command paths are fallback-only when baseline commands are unavailable.
