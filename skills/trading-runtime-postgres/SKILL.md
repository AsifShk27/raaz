---
name: trading-runtime-postgres
description: Operate the trading multi-agent runtime on PostgreSQL hub backend (no file-queue orchestration).
---

# Trading Runtime Postgres Skill

Use this skill when the user asks to:
- run/spawn trading runtime tmux agents without file-queue orchestration
- operate queue/task commands on the Postgres hub backend
- enforce production runtime controls for Raaz + tmux + WhatsApp workflows

## Backend Contract

- Default backend is Postgres (`AGENT_RUNTIME_BACKEND=postgres`).
- File-queue backend is rollback-only (`AGENT_RUNTIME_BACKEND=file`).
- `trpg` pins backend to Postgres even if shell env exports `AGENT_RUNTIME_BACKEND=file`; to force rollback through `trpg`, set `TRPG_ALLOW_FILE_BACKEND=1`.
- Use `agentctl backend` to verify resolved backend.

## Primary Commands

```bash
# Runtime lifecycle
/home/shkas/projects/raaz/skills/trading-runtime-postgres/scripts/trpg start
/home/shkas/projects/raaz/skills/trading-runtime-postgres/scripts/trpg status
/home/shkas/projects/raaz/skills/trading-runtime-postgres/scripts/trpg attach
/home/shkas/projects/raaz/skills/trading-runtime-postgres/scripts/trpg stop

# Task operations (Postgres hub)
/home/shkas/projects/raaz/skills/trading-runtime-postgres/scripts/trpg queue --role worker --summary "Investigate X"
/home/shkas/projects/raaz/skills/trading-runtime-postgres/scripts/trpg list
/home/shkas/projects/raaz/skills/trading-runtime-postgres/scripts/trpg show WORK-...
/home/shkas/projects/raaz/skills/trading-runtime-postgres/scripts/trpg complete WORK-... --result "Done"
/home/shkas/projects/raaz/skills/trading-runtime-postgres/scripts/trpg fail WORK-... --error "Blocked by Y"
/home/shkas/projects/raaz/skills/trading-runtime-postgres/scripts/trpg stats
```

## Session Hygiene

- Prefer explicit session names for parallel investigations:

```bash
AGENT_TMUX_SESSION=agents-prod /home/shkas/projects/raaz/skills/trading-runtime-postgres/scripts/trpg start
```

- Attach to a specific session:

```bash
AGENT_TMUX_SESSION=agents-prod /home/shkas/projects/raaz/skills/trading-runtime-postgres/scripts/trpg attach
```

## Rollback

If emergency rollback to legacy orchestration is required:

```bash
AGENT_RUNTIME_BACKEND=file /home/shkas/trading-agent-runtime/bin/agentctl start
# via trpg wrapper
TRPG_ALLOW_FILE_BACKEND=1 AGENT_RUNTIME_BACKEND=file /home/shkas/projects/raaz/skills/trading-runtime-postgres/scripts/trpg start
```
