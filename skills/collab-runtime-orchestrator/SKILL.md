---
name: collab-runtime-orchestrator
description: Start, monitor, and await staged postgres collaboration sessions (research -> analyze -> agree -> execute -> verify by default).
metadata: {"openclaw":{"emoji":"🧩","requires":{"bins":["bash"]}}}
---

# Collab Runtime Orchestrator

Production wrapper for staged multi-agent collaboration on the postgres backend.

## Workflow

1. `start` creates a session and queues staged tasks:
   - staged-v2 default: research streams -> analysis streams -> agreement -> execution streams -> verify
   - staged-v1 compatibility: discuss streams -> agreement -> execution streams -> verify
2. workers auto-claim tasks
3. `status` reports stage/task progress
4. `await` blocks until terminal state

## Guardrails (Required)

- Do not manually post extra worker tasks with `trpg queue` after a collab session starts.
- Do not map stream count strictly 1:1 to participant count.
- Stream fanout must be capped by eligible active participants after health + availability gating.
- Prefer the staged protocol outputs:
  - research findings -> analysis cross-review -> agree split -> execute streams -> verify.
  - stream count remains focus-track based, then capped by active eligible participants.

## Script

- `scripts/collab-session.sh`

## Usage

Start a staged session:

```bash
./scripts/collab-session.sh start \
  --topic "Build production-grade agent communication system" \
  --participants codex-1,codex-2,codex-3 \
  --research-streams 3 \
  --analysis-streams 3 \
  --execution-streams 3
```

Preflight behavior:

- `start` runs `agentctl collab-preflight --json` before `collab-start`.
- To bypass preflight for controlled rollback only:
  - `AGENT_COLLAB_SKIP_PREFLIGHT=1 ./scripts/collab-session.sh start ...`
- To allow degraded preflight result (reason required):
  - `./scripts/collab-session.sh start --allow-degraded --degraded-reason "task API intermittent timeout"`

Get status:

```bash
./scripts/collab-session.sh status --session-id <session-id>
```

Await completion:

```bash
./scripts/collab-session.sh await --session-id <session-id> --strict
```

Loopback behavior on verify failure:

- `await --strict` auto-enqueues one execute+verify remediation loop when verify stage fails.
- Default loopback scope is now `full` in this wrapper (`research/analyze/agree/execute/verify` restart for staged-v2).
- Override defaults with:
  - `AGENT_COLLAB_AWAIT_LOOPBACK_ON_VERIFY_FAIL=0` to disable auto-loopback.
  - `AGENT_COLLAB_AWAIT_MAX_LOOPBACKS=<n>` to change max loopback attempts (default `1`).
  - `AGENT_COLLAB_AWAIT_LOOPBACK_SCOPE=execute|full` to control restart scope.
  - direct flags: `--no-loopback-on-verify-fail` / `--loopback-on-verify-fail --max-loopbacks <n>`.

Real-time collaboration tuning (worker wrapper):

- For lower turn-wait latency during active task capture, set:
  - `SWARM_NOTICE_DURING_CAPTURE=1` (deliver live notices while task capture is running)
  - `SWARM_CAPTURE_MAY_WHEN_BUSY=0` (default; optional broadcast chatter does not block active task capture)
  - `SWARM_HUMAN_PREEMPT_TIMEOUT_SECONDS=30` (preempt long task capture when urgent human message waits too long)
  - `SWARM_HUMAN_PREEMPT_MIN_CAPTURE_SECONDS=8` (minimum in-task capture window before preempt is allowed)
  - `SWARM_HUMAN_PREEMPT_MAX_PER_TASK=1` (bounded preemptions per task to avoid thrash)
  - `SWARM_MESSAGE_POLL_INTERVAL_SECONDS=0.2`
  - `SWARM_NOTICE_INJECT_INTERVAL_SECONDS=1.0`
- Trade-off:
  - lower preempt timeout improves responsiveness but can reduce long-task throughput if set too aggressively.

Artifact storage guidance:

- Default runtime behavior uses project-root session paths:
  - `<project-root>/artifacts/collab/<session-id>/...`
- For trading-platform workspace, collab artifacts are externalized to:
  - `/mnt/d/Projects/collab`
  with compatibility symlink:
  - `/mnt/d/Projects/trading-platform/artifacts/collab -> /mnt/d/Projects/collab`
- For trading-platform generated frontend outputs (concept images, debug logs/screenshots, Playwright reports), use the same external root pattern under:
  - `/mnt/d/Projects/collab/trading-platform/...`
  with repository compatibility symlinks preserved at original paths.
- To force explicit external root in a run:
  - `./scripts/collab-session.sh start ... --artifact-root /mnt/d/Projects/collab/<session-id>`
- Memory boundary:
  - keep canonical project memory in-repo (`<project-root>/MEMORY.md` and `<project-root>/memory/**`);
  - use `/mnt/d/Projects/collab` for generated artifacts only (not canonical memory relocation).

## Notes

- Uses `$AGENT_RUNTIME_ROOT/bin/agentctl collab-*`.
- Requires postgres backend.
- `--strict` returns non-zero when any task ends failed/blocked/cancelled.
- Codex worker runtime baseline must remain:
  - `codex -a never -s danger-full-access` for slot1-5 and planner Codex command.
  - `start` persists this baseline into `$AGENT_RUNTIME_ROOT/config.env` (idempotent block).
  - `start` also enforces Claude availability precheck in collab mode:
    - `AGENT_WORKER_AVAILABILITY_ENABLE_CLAUDE_CLI_PROBE=1`
    - `AGENT_WORKER_AVAILABILITY_FAIL_OPEN=0`
    so unauthenticated/rate-limited Claude workers do not auto-claim tasks.
  - Validate with pane `/status` before declaring a collab run healthy.
