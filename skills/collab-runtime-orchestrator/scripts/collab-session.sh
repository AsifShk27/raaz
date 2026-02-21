#!/usr/bin/env bash
set -euo pipefail

RUNTIME_ROOT=${AGENT_RUNTIME_ROOT:-/home/shkas/projects/raaz/.runtime}
AGENTCTL="$RUNTIME_ROOT/bin/agentctl"
RUNTIME_CONFIG="$RUNTIME_ROOT/config.env"
CODEX_FULL_PERMISSION_COMMAND=${CODEX_FULL_PERMISSION_COMMAND:-codex -a never -s danger-full-access}

if [[ ! -x "$AGENTCTL" ]]; then
  echo "agentctl not found at $AGENTCTL" >&2
  exit 2
fi

bool_is_true() {
  case "${1,,}" in
    1|true|yes|on)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

persist_codex_permission_defaults() {
  [[ -f "$RUNTIME_CONFIG" ]] || return 0

  local begin="# BEGIN: collab-runtime-orchestrator codex full-permission defaults"
  local end="# END: collab-runtime-orchestrator codex full-permission defaults"
  if grep -Fq "$begin" "$RUNTIME_CONFIG"; then
    sed -i "/^${begin}$/,/^${end}$/d" "$RUNTIME_CONFIG"
  fi

  cat <<EOF_BLOCK >> "$RUNTIME_CONFIG"
$begin
export AGENT_WORKER_COMMAND_SLOT1="\${AGENT_WORKER_COMMAND_SLOT1:-$CODEX_FULL_PERMISSION_COMMAND}"
export AGENT_WORKER_COMMAND_SLOT2="\${AGENT_WORKER_COMMAND_SLOT2:-$CODEX_FULL_PERMISSION_COMMAND}"
export AGENT_WORKER_COMMAND_SLOT3="\${AGENT_WORKER_COMMAND_SLOT3:-$CODEX_FULL_PERMISSION_COMMAND}"
export AGENT_WORKER_COMMAND_SLOT4="\${AGENT_WORKER_COMMAND_SLOT4:-$CODEX_FULL_PERMISSION_COMMAND}"
export AGENT_WORKER_COMMAND_SLOT5="\${AGENT_WORKER_COMMAND_SLOT5:-$CODEX_FULL_PERMISSION_COMMAND}"
export AGENT_PLANNER_COMMAND="\${AGENT_PLANNER_COMMAND:-$CODEX_FULL_PERMISSION_COMMAND}"
export AGENT_PG_AUTOWORKER_ENABLED="\${AGENT_PG_AUTOWORKER_ENABLED:-1}"
export AGENT_WORKER_AVAILABILITY_PRECHECK_ENABLED="\${AGENT_WORKER_AVAILABILITY_PRECHECK_ENABLED:-1}"
export AGENT_WORKER_AVAILABILITY_ENABLE_CLAUDE_CLI_PROBE="\${AGENT_WORKER_AVAILABILITY_ENABLE_CLAUDE_CLI_PROBE:-1}"
export AGENT_WORKER_AVAILABILITY_FAIL_OPEN="\${AGENT_WORKER_AVAILABILITY_FAIL_OPEN:-0}"
export AGENT_PG_ASSIGNMENT_AVAILABILITY_PRECHECK_ENABLED="\${AGENT_PG_ASSIGNMENT_AVAILABILITY_PRECHECK_ENABLED:-1}"
export AGENT_PG_ENFORCE_TASK_PARTICIPANTS="\${AGENT_PG_ENFORCE_TASK_PARTICIPANTS:-1}"
export AGENT_COLLAB_CREATE_PROPOSAL_DEFAULT="\${AGENT_COLLAB_CREATE_PROPOSAL_DEFAULT:-1}"
export AGENT_COLLAB_HUMAN_APPROVE_PROPOSAL_DEFAULT="\${AGENT_COLLAB_HUMAN_APPROVE_PROPOSAL_DEFAULT:-1}"
export AGENT_COLLAB_PROTOCOL_DEFAULT="\${AGENT_COLLAB_PROTOCOL_DEFAULT:-staged-v2}"
export AGENT_COLLAB_REQUIRE_WEB_RESEARCH_DEFAULT="\${AGENT_COLLAB_REQUIRE_WEB_RESEARCH_DEFAULT:-1}"
export AGENT_COLLAB_ACTIVE_AGENT_MAX_STALE_SECONDS="\${AGENT_COLLAB_ACTIVE_AGENT_MAX_STALE_SECONDS:-120}"
export AGENT_COLLAB_VERIFY_LOOPBACK_SCOPE="\${AGENT_COLLAB_VERIFY_LOOPBACK_SCOPE:-full}"
$end
EOF_BLOCK
}

export_codex_permission_env_defaults() {
  export AGENT_WORKER_COMMAND_SLOT1="${AGENT_WORKER_COMMAND_SLOT1:-$CODEX_FULL_PERMISSION_COMMAND}"
  export AGENT_WORKER_COMMAND_SLOT2="${AGENT_WORKER_COMMAND_SLOT2:-$CODEX_FULL_PERMISSION_COMMAND}"
  export AGENT_WORKER_COMMAND_SLOT3="${AGENT_WORKER_COMMAND_SLOT3:-$CODEX_FULL_PERMISSION_COMMAND}"
  export AGENT_WORKER_COMMAND_SLOT4="${AGENT_WORKER_COMMAND_SLOT4:-$CODEX_FULL_PERMISSION_COMMAND}"
  export AGENT_WORKER_COMMAND_SLOT5="${AGENT_WORKER_COMMAND_SLOT5:-$CODEX_FULL_PERMISSION_COMMAND}"
  export AGENT_PLANNER_COMMAND="${AGENT_PLANNER_COMMAND:-$CODEX_FULL_PERMISSION_COMMAND}"
  export AGENT_PG_AUTOWORKER_ENABLED="${AGENT_PG_AUTOWORKER_ENABLED:-1}"
  export AGENT_WORKER_AVAILABILITY_PRECHECK_ENABLED="${AGENT_WORKER_AVAILABILITY_PRECHECK_ENABLED:-1}"
  export AGENT_WORKER_AVAILABILITY_ENABLE_CLAUDE_CLI_PROBE="${AGENT_WORKER_AVAILABILITY_ENABLE_CLAUDE_CLI_PROBE:-1}"
  export AGENT_WORKER_AVAILABILITY_FAIL_OPEN="${AGENT_WORKER_AVAILABILITY_FAIL_OPEN:-0}"
  export AGENT_PG_ASSIGNMENT_AVAILABILITY_PRECHECK_ENABLED="${AGENT_PG_ASSIGNMENT_AVAILABILITY_PRECHECK_ENABLED:-1}"
  export AGENT_PG_ENFORCE_TASK_PARTICIPANTS="${AGENT_PG_ENFORCE_TASK_PARTICIPANTS:-1}"
  export AGENT_COLLAB_CREATE_PROPOSAL_DEFAULT="${AGENT_COLLAB_CREATE_PROPOSAL_DEFAULT:-1}"
  export AGENT_COLLAB_HUMAN_APPROVE_PROPOSAL_DEFAULT="${AGENT_COLLAB_HUMAN_APPROVE_PROPOSAL_DEFAULT:-1}"
  export AGENT_COLLAB_PROTOCOL_DEFAULT="${AGENT_COLLAB_PROTOCOL_DEFAULT:-staged-v2}"
  export AGENT_COLLAB_REQUIRE_WEB_RESEARCH_DEFAULT="${AGENT_COLLAB_REQUIRE_WEB_RESEARCH_DEFAULT:-1}"
  export AGENT_COLLAB_ACTIVE_AGENT_MAX_STALE_SECONDS="${AGENT_COLLAB_ACTIVE_AGENT_MAX_STALE_SECONDS:-120}"
  export AGENT_COLLAB_VERIFY_LOOPBACK_SCOPE="${AGENT_COLLAB_VERIFY_LOOPBACK_SCOPE:-full}"
}

run_collab_preflight() {
  local allow_degraded_raw="$1"
  local degraded_reason="$2"
  local -a preflight_args=("$AGENTCTL" collab-preflight --json)

  if bool_is_true "$allow_degraded_raw"; then
    if [[ -z "${degraded_reason// }" ]]; then
      echo "Degraded preflight override requires --degraded-reason (or AGENT_COLLAB_PREFLIGHT_DEGRADED_REASON)." >&2
      return 2
    fi
    preflight_args+=(--allow-degraded --degraded-reason "$degraded_reason")
  fi

  "${preflight_args[@]}"
}

cmd=${1:-}
if [[ -z "$cmd" ]]; then
  echo "Usage: $0 <start|status|await> [args...]" >&2
  exit 2
fi
shift || true

case "$cmd" in
  start)
    skip_preflight_raw=${AGENT_COLLAB_SKIP_PREFLIGHT:-0}
    allow_degraded_raw=${AGENT_COLLAB_PREFLIGHT_ALLOW_DEGRADED:-0}
    degraded_reason=${AGENT_COLLAB_PREFLIGHT_DEGRADED_REASON:-}
    forwarded_args=()
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --skip-preflight)
          skip_preflight_raw=1
          shift
          ;;
        --allow-degraded)
          allow_degraded_raw=1
          shift
          ;;
        --degraded-reason)
          if [[ $# -lt 2 ]]; then
            echo "--degraded-reason requires a value" >&2
            exit 2
          fi
          degraded_reason="$2"
          shift 2
          ;;
        *)
          forwarded_args+=("$1")
          shift
          ;;
      esac
    done
    persist_codex_permission_defaults
    export_codex_permission_env_defaults
    if ! bool_is_true "$skip_preflight_raw"; then
      run_collab_preflight "$allow_degraded_raw" "$degraded_reason"
    fi
    exec "$AGENTCTL" collab-start "${forwarded_args[@]}"
    ;;
  status)
    exec "$AGENTCTL" collab-status "$@"
    ;;
  await)
    loopback_on_verify_fail_raw=${AGENT_COLLAB_AWAIT_LOOPBACK_ON_VERIFY_FAIL:-1}
    max_loopbacks=${AGENT_COLLAB_AWAIT_MAX_LOOPBACKS:-1}
    loopback_scope=${AGENT_COLLAB_AWAIT_LOOPBACK_SCOPE:-${AGENT_COLLAB_VERIFY_LOOPBACK_SCOPE:-full}}
    if bool_is_true "$loopback_on_verify_fail_raw"; then
      exec "$AGENTCTL" collab-await --loopback-on-verify-fail --max-loopbacks "$max_loopbacks" --loopback-scope "$loopback_scope" "$@"
    fi
    exec "$AGENTCTL" collab-await --no-loopback-on-verify-fail --max-loopbacks "$max_loopbacks" --loopback-scope "$loopback_scope" "$@"
    ;;
  *)
    echo "Unknown command: $cmd" >&2
    exit 2
    ;;
esac
