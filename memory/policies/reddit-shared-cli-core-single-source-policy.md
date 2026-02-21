# Policy: Reddit Shared CLI Core Single-Source Contract

Date: 2026-02-21
Status: Active
Owner: Raaz skills domain

## Policy

- All Raaz Reddit skills must use the shared core implementation in:
  - `skills/reddit-cli/lib/reddit_api.py`
- Reddit skills must not maintain separate bespoke HTTP/auth/client implementations.
- Default auth mode for production-capable Reddit jobs must be `auto`:
  - OAuth when credentials are present,
  - public mode only as fallback.

## Rationale

- Prevent reliability drift and inconsistent behavior between trend and sentiment skills.
- Keep transport/auth fixes centralized (including anti-bot behavior handling).
- Reduce maintenance burden and incident recovery time.

## Enforcement

- Any Reddit skill change that introduces local duplicate HTTP/auth code is policy non-compliant.
- Shared core changes require smoke validation via:
  - `reddit_cli.py check`
  - `reddit_cli.py posts`
  - one sentiment run + one trend run

## Rollback note

- In emergency cases, skills may temporarily pin prior versions, but canonical remediation path remains shared-core convergence.
