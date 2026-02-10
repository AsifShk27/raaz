#!/usr/bin/env bash
set -euo pipefail

DEFAULT_SOCKET="/home/shkas/projects/raaz/.clawdhub/tmux/codex-army.sock"
DEFAULT_SESSION="collab-test"
DEFAULT_WINDOW="collab-test"
DEFAULT_WORKSPACE_BASE="/home/shkas/projects/raaz/.clawdhub/workspaces"
DEFAULT_RUNTIME_PROFILE_SCRIPT="/mnt/d/projects/trading-platform/scripts/prepare_agent_runtime.sh"
DEFAULT_WAIT_TIMEOUT="25"
DEFAULT_ENTER_DELAY="0.15"

AGENT_NAMES=(codex codex-patch codex-circuit codex-4 codex-5)
AGENT_WORKSPACES_DEFAULT=(codex codex-patch codex-circuit codex-4 codex-5)
AGENT_COMMANDS_DEFAULT=(codex codex codex codex codex)
RUNTIME_SLOT_WORKSPACES=()
RUNTIME_SLOT_COMMANDS=()

usage() {
  cat <<'USAGE'
codex-collab.sh - deterministic tmux orchestration for Codex collab panes.

Usage:
  codex-collab.sh start [options]
  codex-collab.sh status [options]
  codex-collab.sh send --agent <name|pane-index|session:window.pane> [--text "..."] [--file path] [options]
  codex-collab.sh broadcast [--text "..."] [--file path] [options]
  codex-collab.sh capture --agent <name|pane-index|session:window.pane> [--lines N] [options]
  codex-collab.sh stop [options]

Shared options:
  --socket <path>            tmux socket path
  --session <name>           tmux session name
  --window <name>            tmux window name
  --workspace-base <path>    base workspace directory
  --workspace-source <mode>  workspace mapping source: runtime|static (default: runtime)
  --runtime-profile-script   runtime profile wrapper path (default: /mnt/d/projects/trading-platform/scripts/prepare_agent_runtime.sh)

start options:
  --replace-window <0|1>     replace existing target window (default: 1)
  --wait-timeout <seconds>   wait timeout for Codex process readiness (default: 25)

send/broadcast options:
  --text <prompt>            prompt text to send
  --file <path>              prompt text file to send
  --allow-shell <0|1>        allow send when pane process is shell (default: 0)
  --allow-gated <0|1>        allow send when Codex login/workspace-trust gate is detected (default: 0)
  --enter-delay <seconds>    delay before Enter key after paste (default: 0.15)

capture options:
  --lines <N>                number of lines to capture (default: 80)

stop options:
  --kill-session <0|1>       kill entire tmux session instead of window (default: 0)

Examples:
  codex-collab.sh start
  codex-collab.sh status
  codex-collab.sh send --agent codex --text "Investigate kafka consumer lag and propose fix."
  codex-collab.sh broadcast --file /tmp/task.txt
USAGE
}

log() {
  printf '[codex-collab] %s\n' "$*" >&2
}

die() {
  log "$*"
  exit 1
}

is_true() {
  case "${1,,}" in
    1|true|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

tmuxs() {
  local socket="$1"
  shift
  tmux -S "$socket" "$@"
}

require_tmux() {
  command -v tmux >/dev/null 2>&1 || die "tmux not found on PATH."
}

window_exists() {
  local socket="$1"
  local session="$2"
  local window="$3"
  tmuxs "$socket" list-windows -t "$session" -F "#{window_name}" 2>/dev/null | grep -Fxq "$window"
}

resolve_workspace_path() {
  local workspace_base="$1"
  local workspace="$2"
  if [[ "$workspace" == /* ]]; then
    printf '%s' "$workspace"
    return 0
  fi
  printf '%s/%s' "$workspace_base" "$workspace"
}

load_runtime_slot_profile() {
  local profile_script="$1"
  [[ -f "$profile_script" ]] || return 1

  local profile_output=""
  if [[ -x "$profile_script" ]]; then
    profile_output=$("$profile_script" profile 2>/dev/null) || return 1
  else
    profile_output=$(bash "$profile_script" profile 2>/dev/null) || return 1
  fi
  [[ -n "$profile_output" ]] || return 1

  local -A profile_map=()
  local line key value
  while IFS= read -r line; do
    [[ "$line" == *=* ]] || continue
    key="${line%%=*}"
    value="${line#*=}"
    profile_map["$key"]="$value"
  done <<< "$profile_output"

  local -a workspaces=()
  local -a commands=()
  local slot entry cmd workspace
  for slot in 1 2 3 4 5; do
    entry="${profile_map[slot${slot}]:-}"
    [[ -n "$entry" ]] || return 1
    [[ "$entry" == *:* ]] || return 1
    cmd="${entry%%:*}"
    workspace="${entry#*:}"
    [[ -n "$cmd" && -n "$workspace" ]] || return 1
    commands+=("$cmd")
    workspaces+=("$workspace")
  done

  RUNTIME_SLOT_WORKSPACES=("${workspaces[@]}")
  RUNTIME_SLOT_COMMANDS=("${commands[@]}")
  return 0
}

expected_process_for_command() {
  local command="$1"
  local root="${command%% *}"
  basename "$root"
}

process_matches_command() {
  local command="$1"
  local process="$2"
  local expected
  expected=$(expected_process_for_command "$command")

  if [[ "$process" == "$expected" ]]; then
    return 0
  fi

  # Codex/Claude CLIs commonly run as a Node foreground process in tmux panes.
  if [[ "$expected" == "codex" || "$expected" == "claude" ]] && [[ "$process" == "node" ]]; then
    return 0
  fi

  return 1
}

launch_interactive_pane() {
  local socket="$1"
  local pane_target="$2"
  local workspace="$3"
  local command="$4"
  local root
  root=$(basename "${command%% *}")
  local env_prefix=""
  case "${root,,}" in
    codex*)
      env_prefix="export CODEX_HOME=\"$workspace\" && "
      ;;
    claude*)
      env_prefix="export CLAUDE_HOME=\"$workspace\" && "
      ;;
  esac
  local inner="cd \"$workspace\" && ${env_prefix}exec $command"
  local escaped
  escaped=$(printf '%q' "$inner")
  tmuxs "$socket" respawn-pane -k -t "$pane_target" "bash -lc $escaped"
}

wait_for_pane_process() {
  local socket="$1"
  local pane_target="$2"
  local command="$3"
  local timeout="$4"
  local start now current

  start=$(date +%s)
  while true; do
    current=$(tmuxs "$socket" display-message -p -t "$pane_target" "#{pane_current_command}" 2>/dev/null || true)
    if process_matches_command "$command" "$current"; then
      return 0
    fi
    now=$(date +%s)
    if (( now - start >= timeout )); then
      return 1
    fi
    sleep 0.25
  done
}

pane_gate_state() {
  local socket="$1"
  local pane_target="$2"
  local command="$3"
  local expected
  expected=$(expected_process_for_command "$command")

  if [[ "$expected" != "codex" ]]; then
    printf 'ready'
    return 0
  fi

  local pane_text
  pane_text=$(tmuxs "$socket" capture-pane -p -J -S -80 -t "$pane_target" 2>/dev/null || true)
  if printf '%s\n' "$pane_text" | grep -Eq "Sign in with ChatGPT|Provide your own API key|Finish signing in via your browser"; then
    printf 'login'
    return 0
  fi
  if printf '%s\n' "$pane_text" | grep -Eq "allow Codex to work in this folder without asking for approval|Press enter to continue"; then
    printf 'workspace-trust'
    return 0
  fi

  printf 'ready'
}

print_status_table() {
  local socket="$1"
  local session="$2"
  local window="$3"

  printf "%-4s %-14s %-10s %-7s %-15s %s\n" "Pane" "Agent" "Process" "Ready" "Gate" "Workspace"
  while IFS='|' read -r pane_index pane_cmd pane_path pane_agent pane_workspace pane_command; do
    local ready gate
    ready="no"
    if process_matches_command "${pane_command:-codex}" "${pane_cmd:-}"; then
      ready="yes"
    fi
    gate=$(pane_gate_state "$socket" "$session:$window.$pane_index" "${pane_command:-codex}")
    if [[ "$gate" != "ready" ]]; then
      ready="no"
    fi
    printf "%-4s %-14s %-10s %-7s %-15s %s\n" \
      "${pane_index:-?}" \
      "${pane_agent:-unknown}" \
      "${pane_cmd:-?}" \
      "$ready" \
      "$gate" \
      "${pane_workspace:-$pane_path}"
  done < <(tmuxs "$socket" list-panes -t "$session:$window" \
    -F "#{pane_index}|#{pane_current_command}|#{pane_current_path}|#{@collab_agent}|#{@collab_workspace}|#{@collab_command}" \
    2>/dev/null | sort -t'|' -k1,1n)
}

resolve_target_pane() {
  local socket="$1"
  local session="$2"
  local window="$3"
  local selector="$4"

  if [[ "$selector" == *:*.* ]]; then
    printf '%s' "$selector"
    return 0
  fi

  if [[ "$selector" =~ ^[0-9]+$ ]]; then
    printf '%s' "$session:$window.$selector"
    return 0
  fi

  while IFS='|' read -r pane_index pane_agent; do
    if [[ "$pane_agent" == "$selector" ]]; then
      printf '%s' "$session:$window.$pane_index"
      return 0
    fi
  done < <(tmuxs "$socket" list-panes -t "$session:$window" -F "#{pane_index}|#{@collab_agent}" 2>/dev/null)

  return 1
}

read_prompt_text() {
  local inline_text="$1"
  local file_path="$2"
  local prompt

  if [[ -n "$inline_text" && -n "$file_path" ]]; then
    die "Use only one of --text or --file."
  fi

  if [[ -n "$file_path" ]]; then
    [[ -f "$file_path" ]] || die "Prompt file not found: $file_path"
    prompt=$(cat "$file_path")
    printf '%s' "$prompt"
    return 0
  fi

  if [[ -n "$inline_text" ]]; then
    printf '%s' "$inline_text"
    return 0
  fi

  if [[ ! -t 0 ]]; then
    prompt=$(cat)
    printf '%s' "$prompt"
    return 0
  fi

  die "Prompt missing. Provide --text, --file, or pipe stdin."
}

ensure_interactive_target() {
  local socket="$1"
  local pane_target="$2"
  local allow_shell="$3"
  local allow_gated="$4"

  local current expected_raw gate
  current=$(tmuxs "$socket" display-message -p -t "$pane_target" "#{pane_current_command}" 2>/dev/null || true)
  expected_raw=$(tmuxs "$socket" display-message -p -t "$pane_target" "#{@collab_command}" 2>/dev/null || true)
  gate=$(pane_gate_state "$socket" "$pane_target" "${expected_raw:-codex}")

  if process_matches_command "${expected_raw:-codex}" "$current"; then
    if [[ "$gate" == "ready" ]]; then
      return 0
    fi
    if is_true "$allow_gated"; then
      log "Warning: target $pane_target has gate='$gate'; sending anyway (--allow-gated=1)."
      return 0
    fi
    die "Target $pane_target is interactive but gated (gate='$gate'). Clear the gate before dispatch, or pass --allow-gated 1."
  fi

  if is_true "$allow_shell"; then
    log "Warning: target $pane_target is running '$current' (expected command '${expected_raw:-codex}'); sending anyway (--allow-shell=1)."
    return 0
  fi

  die "Target $pane_target is not interactive (process='$current', expected command='${expected_raw:-codex}'). Run start/status before sending."
}

send_prompt_to_pane() {
  local socket="$1"
  local pane_target="$2"
  local prompt="$3"
  local enter_delay="$4"

  local buffer_name="collab-send-$RANDOM-$$"
  printf '%s' "$prompt" | tmuxs "$socket" load-buffer -b "$buffer_name" -
  tmuxs "$socket" paste-buffer -t "$pane_target" -b "$buffer_name" -p
  tmuxs "$socket" delete-buffer -b "$buffer_name" >/dev/null 2>&1 || true
  sleep "$enter_delay"
  tmuxs "$socket" send-keys -t "$pane_target" Enter
}

cmd_start() {
  local socket="$DEFAULT_SOCKET"
  local session="$DEFAULT_SESSION"
  local window="$DEFAULT_WINDOW"
  local workspace_base="$DEFAULT_WORKSPACE_BASE"
  local workspace_source="runtime"
  local runtime_profile_script="$DEFAULT_RUNTIME_PROFILE_SCRIPT"
  local replace_window="1"
  local wait_timeout="$DEFAULT_WAIT_TIMEOUT"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --socket) socket="$2"; shift 2 ;;
      --session) session="$2"; shift 2 ;;
      --window) window="$2"; shift 2 ;;
      --workspace-base) workspace_base="$2"; shift 2 ;;
      --workspace-source) workspace_source="$2"; shift 2 ;;
      --runtime-profile-script) runtime_profile_script="$2"; shift 2 ;;
      --replace-window) replace_window="$2"; shift 2 ;;
      --wait-timeout) wait_timeout="$2"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) die "Unknown start option: $1" ;;
    esac
  done

  [[ "$wait_timeout" =~ ^[0-9]+$ ]] || die "--wait-timeout must be an integer."
  case "$workspace_source" in
    runtime|static)
      ;;
    *)
      die "--workspace-source must be runtime or static."
      ;;
  esac

  require_tmux
  mkdir -p "$(dirname "$socket")"

  local -a agent_workspaces=("${AGENT_WORKSPACES_DEFAULT[@]}")
  local -a agent_commands=("${AGENT_COMMANDS_DEFAULT[@]}")
  if [[ "$workspace_source" == "runtime" ]]; then
    if load_runtime_slot_profile "$runtime_profile_script"; then
      agent_workspaces=("${RUNTIME_SLOT_WORKSPACES[@]}")
      agent_commands=("${RUNTIME_SLOT_COMMANDS[@]}")
      log "Loaded slot1-5 workspace mapping from runtime profile: $runtime_profile_script"
    else
      log "Warning: unable to load runtime slot mapping from '$runtime_profile_script'; using static workspace defaults."
    fi
  fi

  local idx
  for idx in "${!agent_workspaces[@]}"; do
    mkdir -p "$(resolve_workspace_path "$workspace_base" "${agent_workspaces[$idx]}")"
  done

  if ! tmuxs "$socket" has-session -t "$session" 2>/dev/null; then
    tmuxs "$socket" new-session -d -s "$session" -n bootstrap -c "$(resolve_workspace_path "$workspace_base" "${agent_workspaces[0]}")"
  fi

  if window_exists "$socket" "$session" "$window"; then
    if is_true "$replace_window"; then
      tmuxs "$socket" kill-window -t "$session:$window"
    else
      die "Window $session:$window already exists. Re-run with --replace-window 1."
    fi
  fi

  tmuxs "$socket" new-window -d -t "$session" -n "$window" -c "$(resolve_workspace_path "$workspace_base" "${agent_workspaces[0]}")"
  local pane_target_count="${#AGENT_NAMES[@]}"
  for ((idx=1; idx<pane_target_count; idx++)); do
    tmuxs "$socket" split-window -t "$session:$window" -c "$(resolve_workspace_path "$workspace_base" "${agent_workspaces[$idx]}")"
    tmuxs "$socket" select-layout -t "$session:$window" tiled >/dev/null 2>&1 || true
  done
  tmuxs "$socket" select-layout -t "$session:$window" tiled >/dev/null 2>&1 || true

  local -a pane_indices=()
  mapfile -t pane_indices < <(tmuxs "$socket" list-panes -t "$session:$window" -F "#{pane_index}" | sort -n)
  if (( ${#pane_indices[@]} != pane_target_count )); then
    die "Expected $pane_target_count panes, found ${#pane_indices[@]} in $session:$window."
  fi

  for idx in "${!AGENT_NAMES[@]}"; do
    local pane="$session:$window.${pane_indices[$idx]}"
    local agent="${AGENT_NAMES[$idx]}"
    local command="${agent_commands[$idx]}"
    local workspace
    workspace="$(resolve_workspace_path "$workspace_base" "${agent_workspaces[$idx]}")"
    local title="agent:$agent"

    tmuxs "$socket" set-option -p -t "$pane" @collab_agent "$agent"
    tmuxs "$socket" set-option -p -t "$pane" @collab_workspace "$workspace"
    tmuxs "$socket" set-option -p -t "$pane" @collab_command "$command"
    tmuxs "$socket" set-option -p -t "$pane" remain-on-exit on >/dev/null 2>&1 || true
    tmuxs "$socket" select-pane -t "$pane" -T "$title" >/dev/null 2>&1 || true

    launch_interactive_pane "$socket" "$pane" "$workspace" "$command"
  done

  local failures=0
  for idx in "${!AGENT_NAMES[@]}"; do
    local pane="$session:$window.${pane_indices[$idx]}"
    if ! wait_for_pane_process "$socket" "$pane" "${agent_commands[$idx]}" "$wait_timeout"; then
      failures=$((failures + 1))
      log "Pane $pane (${AGENT_NAMES[$idx]}) failed readiness check (expected command: ${agent_commands[$idx]})."
    fi
  done

  tmuxs "$socket" select-pane -t "$session:$window.${pane_indices[0]}" >/dev/null 2>&1 || true

  print_status_table "$socket" "$session" "$window"
  printf '\n'
  printf 'Monitor: tmux -S %q attach -t %q\n' "$socket" "$session"
  printf 'Check:   %q status --socket %q --session %q --window %q\n' "$0" "$socket" "$session" "$window"

  if (( failures > 0 )); then
    die "Started with $failures readiness failure(s). Run status/capture before dispatching work."
  fi
}

cmd_status() {
  local socket="$DEFAULT_SOCKET"
  local session="$DEFAULT_SESSION"
  local window="$DEFAULT_WINDOW"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --socket) socket="$2"; shift 2 ;;
      --session) session="$2"; shift 2 ;;
      --window) window="$2"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) die "Unknown status option: $1" ;;
    esac
  done

  require_tmux
  tmuxs "$socket" has-session -t "$session" 2>/dev/null || die "Session not found: $session"
  window_exists "$socket" "$session" "$window" || die "Window not found: $session:$window"
  print_status_table "$socket" "$session" "$window"
}

cmd_send() {
  local socket="$DEFAULT_SOCKET"
  local session="$DEFAULT_SESSION"
  local window="$DEFAULT_WINDOW"
  local selector=""
  local inline_text=""
  local file_path=""
  local allow_shell="0"
  local allow_gated="0"
  local enter_delay="$DEFAULT_ENTER_DELAY"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --socket) socket="$2"; shift 2 ;;
      --session) session="$2"; shift 2 ;;
      --window) window="$2"; shift 2 ;;
      --agent) selector="$2"; shift 2 ;;
      --text) inline_text="$2"; shift 2 ;;
      --file) file_path="$2"; shift 2 ;;
      --allow-shell) allow_shell="$2"; shift 2 ;;
      --allow-gated) allow_gated="$2"; shift 2 ;;
      --enter-delay) enter_delay="$2"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) die "Unknown send option: $1" ;;
    esac
  done

  [[ -n "$selector" ]] || die "send requires --agent <name|pane-index|session:window.pane>."

  require_tmux
  tmuxs "$socket" has-session -t "$session" 2>/dev/null || die "Session not found: $session"
  window_exists "$socket" "$session" "$window" || die "Window not found: $session:$window"

  local pane_target
  pane_target=$(resolve_target_pane "$socket" "$session" "$window" "$selector") || die "Unknown agent selector: $selector"
  tmuxs "$socket" display-message -p -t "$pane_target" "#{pane_id}" >/dev/null 2>&1 || die "Pane not found: $pane_target"

  local prompt
  prompt=$(read_prompt_text "$inline_text" "$file_path")
  [[ -n "$prompt" ]] || die "Prompt is empty."

  ensure_interactive_target "$socket" "$pane_target" "$allow_shell" "$allow_gated"
  send_prompt_to_pane "$socket" "$pane_target" "$prompt" "$enter_delay"
  log "Sent prompt to $pane_target"
}

cmd_broadcast() {
  local socket="$DEFAULT_SOCKET"
  local session="$DEFAULT_SESSION"
  local window="$DEFAULT_WINDOW"
  local inline_text=""
  local file_path=""
  local allow_shell="0"
  local allow_gated="0"
  local enter_delay="$DEFAULT_ENTER_DELAY"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --socket) socket="$2"; shift 2 ;;
      --session) session="$2"; shift 2 ;;
      --window) window="$2"; shift 2 ;;
      --text) inline_text="$2"; shift 2 ;;
      --file) file_path="$2"; shift 2 ;;
      --allow-shell) allow_shell="$2"; shift 2 ;;
      --allow-gated) allow_gated="$2"; shift 2 ;;
      --enter-delay) enter_delay="$2"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) die "Unknown broadcast option: $1" ;;
    esac
  done

  require_tmux
  tmuxs "$socket" has-session -t "$session" 2>/dev/null || die "Session not found: $session"
  window_exists "$socket" "$session" "$window" || die "Window not found: $session:$window"

  local prompt
  prompt=$(read_prompt_text "$inline_text" "$file_path")
  [[ -n "$prompt" ]] || die "Prompt is empty."

  local pane
  while IFS='|' read -r pane_index pane_agent; do
    pane="$session:$window.$pane_index"
    ensure_interactive_target "$socket" "$pane" "$allow_shell" "$allow_gated"
    send_prompt_to_pane "$socket" "$pane" "$prompt" "$enter_delay"
    log "Broadcast prompt sent to ${pane_agent:-pane-$pane_index} ($pane)"
  done < <(tmuxs "$socket" list-panes -t "$session:$window" -F "#{pane_index}|#{@collab_agent}" 2>/dev/null | sort -t'|' -k1,1n)
}

cmd_capture() {
  local socket="$DEFAULT_SOCKET"
  local session="$DEFAULT_SESSION"
  local window="$DEFAULT_WINDOW"
  local selector=""
  local lines="80"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --socket) socket="$2"; shift 2 ;;
      --session) session="$2"; shift 2 ;;
      --window) window="$2"; shift 2 ;;
      --agent) selector="$2"; shift 2 ;;
      --lines) lines="$2"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) die "Unknown capture option: $1" ;;
    esac
  done

  [[ "$lines" =~ ^[0-9]+$ ]] || die "--lines must be an integer."
  [[ -n "$selector" ]] || die "capture requires --agent <name|pane-index|session:window.pane>."

  require_tmux
  local pane_target
  pane_target=$(resolve_target_pane "$socket" "$session" "$window" "$selector") || die "Unknown agent selector: $selector"
  tmuxs "$socket" capture-pane -p -J -S "-$lines" -t "$pane_target"
}

cmd_stop() {
  local socket="$DEFAULT_SOCKET"
  local session="$DEFAULT_SESSION"
  local window="$DEFAULT_WINDOW"
  local kill_session="0"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --socket) socket="$2"; shift 2 ;;
      --session) session="$2"; shift 2 ;;
      --window) window="$2"; shift 2 ;;
      --kill-session) kill_session="$2"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) die "Unknown stop option: $1" ;;
    esac
  done

  require_tmux
  tmuxs "$socket" has-session -t "$session" 2>/dev/null || die "Session not found: $session"
  if is_true "$kill_session"; then
    tmuxs "$socket" kill-session -t "$session"
    log "Killed session $session"
    return 0
  fi

  window_exists "$socket" "$session" "$window" || die "Window not found: $session:$window"
  tmuxs "$socket" kill-window -t "$session:$window"
  log "Killed window $session:$window"
}

main() {
  local subcommand="${1:-}"
  if [[ -z "$subcommand" ]]; then
    usage
    exit 1
  fi
  shift || true

  case "$subcommand" in
    start) cmd_start "$@" ;;
    status) cmd_status "$@" ;;
    send) cmd_send "$@" ;;
    broadcast) cmd_broadcast "$@" ;;
    capture) cmd_capture "$@" ;;
    stop) cmd_stop "$@" ;;
    -h|--help|help) usage ;;
    *) die "Unknown subcommand: $subcommand" ;;
  esac
}

main "$@"
