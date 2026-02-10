---
name: tmux
description: Remote-control tmux sessions for interactive CLIs by sending keystrokes and scraping pane output.
metadata:
  { "openclaw": { "emoji": "🧵", "os": ["darwin", "linux"], "requires": { "bins": ["tmux"] } } }
---

# tmux Skill (OpenClaw)

Use tmux only when you need an interactive TTY. Prefer exec background mode for long-running, non-interactive tasks.

## Quickstart (isolated socket, exec tool)

```bash
SOCKET_DIR="${OPENCLAW_TMUX_SOCKET_DIR:-${CLAWDBOT_TMUX_SOCKET_DIR:-${TMPDIR:-/tmp}/openclaw-tmux-sockets}}"
mkdir -p "$SOCKET_DIR"
SOCKET="$SOCKET_DIR/openclaw.sock"
SESSION=openclaw-python

tmux -S "$SOCKET" new -d -s "$SESSION" -n shell
tmux -S "$SOCKET" send-keys -t "$SESSION":0.0 -- 'PYTHON_BASIC_REPL=1 python3 -q' Enter
tmux -S "$SOCKET" capture-pane -p -J -t "$SESSION":0.0 -S -200
```

After starting a session, always print monitor commands:

```
To monitor:
  tmux -S "$SOCKET" attach -t "$SESSION"
  tmux -S "$SOCKET" capture-pane -p -J -t "$SESSION":0.0 -S -200
```

## Socket convention

- Use `OPENCLAW_TMUX_SOCKET_DIR` (legacy `CLAWDBOT_TMUX_SOCKET_DIR` also supported).
- Default socket path: `"$OPENCLAW_TMUX_SOCKET_DIR/openclaw.sock"`.

## Targeting panes and naming

- Target format: `session:window.pane` (defaults to `:0.0`).
- Keep names short; avoid spaces.
- Inspect: `tmux -S "$SOCKET" list-sessions`, `tmux -S "$SOCKET" list-panes -a`.

## Finding sessions

- List sessions on your socket: `{baseDir}/scripts/find-sessions.sh -S "$SOCKET"`.
- Scan all sockets: `{baseDir}/scripts/find-sessions.sh --all` (uses `OPENCLAW_TMUX_SOCKET_DIR`).

## Persistent Codex Workspaces (Raaz)

For Raaz collab Codex agents, prefer persistent paths and never default to `/tmp` workdirs.

Workspace map:

- `codex` -> `/home/shkas/projects/raaz/.clawdhub/workspaces/codex`
- `codex-patch` -> `/home/shkas/projects/raaz/.clawdhub/workspaces/codex-patch`
- `codex-circuit` -> `/home/shkas/projects/raaz/.clawdhub/workspaces/codex-circuit`
- `codex-4` -> `/home/shkas/projects/raaz/.clawdhub/workspaces/codex-4`
- `codex-5` -> `/home/shkas/projects/raaz/.clawdhub/workspaces/codex-5`

Persistent socket:

- `SOCKET=/home/shkas/projects/raaz/.clawdhub/tmux/codex-army.sock`

Create sessions with `-c <workspace>` so each session starts in its own persistent directory.

## Production Collab Bootstrap (Required)

For multi-agent Codex collaboration demos, do not hand-roll pane creation with raw `new-window/split-window` plus shell `echo` tasks.
That creates plain shell panes and produces fake "agent work" transcripts.

Use the deterministic helper instead:

```bash
SOCKET="/home/shkas/projects/raaz/.clawdhub/tmux/codex-army.sock"
{baseDir}/scripts/codex-collab.sh start --socket "$SOCKET" --session collab-test --window collab-test
{baseDir}/scripts/codex-collab.sh status --socket "$SOCKET" --session collab-test --window collab-test
```

By default, `start` pulls slot1-slot5 workspace/command mapping from the live runtime profile:

- `/mnt/d/projects/trading-platform/scripts/prepare_agent_runtime.sh profile`
- this keeps collab panes aligned with the same persistent workspaces used by the current agent runtime.

You can force static mapping only when needed:

```bash
{baseDir}/scripts/codex-collab.sh start --socket "$SOCKET" --session collab-test --window collab-test --workspace-source static
```

Dispatch work only through helper commands (they enforce interactive-process checks):

```bash
{baseDir}/scripts/codex-collab.sh send --socket "$SOCKET" --session collab-test --window collab-test --agent codex --text "Research AWS AgentCore fit for DDOPs."
{baseDir}/scripts/codex-collab.sh send --socket "$SOCKET" --session collab-test --window collab-test --agent codex-5 --file /tmp/task.txt
```

Before claiming "agents are working", confirm `status` shows:

- `Process` is the expected interactive CLI process (`codex`/`claude`, or `node` for their foreground runtime).
- `Gate` is `ready` (not `login` or `workspace-trust`).

If `Gate` is not `ready`, clear it first in the pane (login/workspace trust flow) or use explicit override flags (`--allow-gated 1`) only when intentionally bypassing safeguards.

## Sending input safely

- Prefer literal sends: `tmux -S "$SOCKET" send-keys -t target -l -- "$cmd"`.
- Control keys: `tmux -S "$SOCKET" send-keys -t target C-c`.
- For interactive TUI apps like Claude Code/Codex, this guidance covers **how to send commands**.
  Do **not** append `Enter` in the same `send-keys`. These apps may treat a fast text+Enter
  sequence as paste/multi-line input and not submit; this is timing-dependent. Send text and
  `Enter` as separate commands with a small delay (tune per environment; increase if needed,
  or use `sleep 1` if sub-second sleeps aren't supported):

```bash
tmux -S "$SOCKET" send-keys -t target -l -- "$cmd" && sleep 0.1 && tmux -S "$SOCKET" send-keys -t target Enter
```

## Watching output

- Capture recent history: `tmux -S "$SOCKET" capture-pane -p -J -t target -S -200`.
- Wait for prompts: `{baseDir}/scripts/wait-for-text.sh -t session:0.0 -p 'pattern'`.
- Attaching is OK; detach with `Ctrl+b d`.

## Spawning processes

- For python REPLs, set `PYTHON_BASIC_REPL=1` (non-basic REPL breaks send-keys flows).

## Windows / WSL

- tmux is supported on macOS/Linux. On Windows, use WSL and install tmux inside WSL.
- This skill is gated to `darwin`/`linux` and requires `tmux` on PATH.

## Orchestrating Coding Agents (Codex, Claude Code)

tmux excels at running multiple coding agents in parallel:

```bash
SOCKET="/home/shkas/projects/raaz/.clawdhub/tmux/codex-army.sock"

# Bootstrap a 5-agent collab window with interactive Codex CLIs.
{baseDir}/scripts/codex-collab.sh start --socket "$SOCKET" --session collab-test --window collab-test

# Verify panes are interactive (process should be codex, not bash).
{baseDir}/scripts/codex-collab.sh status --socket "$SOCKET" --session collab-test --window collab-test

# Send targeted tasks.
{baseDir}/scripts/codex-collab.sh send --socket "$SOCKET" --session collab-test --window collab-test --agent codex-4 --text "Fix bug X."
{baseDir}/scripts/codex-collab.sh send --socket "$SOCKET" --session collab-test --window collab-test --agent codex-5 --text "Fix bug Y."

# Capture output.
{baseDir}/scripts/codex-collab.sh capture --socket "$SOCKET" --session collab-test --window collab-test --agent codex-4 --lines 120
```

**Tips:**

- Use separate git worktrees for parallel fixes (no branch conflicts)
- `pnpm install` first before running codex in fresh clones
- Check process state with `codex-collab.sh status` before/after dispatch
- Codex needs `--yolo` or `--full-auto` for non-interactive fixes

## Cleanup

- Kill a session: `tmux -S "$SOCKET" kill-session -t "$SESSION"`.
- Kill all sessions on a socket: `tmux -S "$SOCKET" list-sessions -F '#{session_name}' | xargs -r -n1 tmux -S "$SOCKET" kill-session -t`.
- Remove everything on the private socket: `tmux -S "$SOCKET" kill-server`.

## Helper: wait-for-text.sh

`{baseDir}/scripts/wait-for-text.sh` polls a pane for a regex (or fixed string) with a timeout.

```bash
{baseDir}/scripts/wait-for-text.sh -t session:0.0 -p 'pattern' [-F] [-T 20] [-i 0.5] [-l 2000]
```

- `-t`/`--target` pane target (required)
- `-p`/`--pattern` regex to match (required); add `-F` for fixed string
- `-T` timeout seconds (integer, default 15)
- `-i` poll interval seconds (default 0.5)
- `-l` history lines to search (integer, default 1000)
