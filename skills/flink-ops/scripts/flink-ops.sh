#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="streaming"
JOB=""
TAIL=200
YES=0

usage() {
  cat <<USAGE
Usage: $(basename "$0") <command> [options]

Commands:
  status                 Show FlinkDeployment status and related pods
  logs                   Show logs for pods matching --job
  restart                Trigger restartNonce bump on --job
  suspend                Set .spec.job.state=suspended for --job
  resume                 Set .spec.job.state=running for --job
  savepoint              Trigger savepoint nonce bump for --job

Options:
  -n, --namespace <ns>   Namespace (default: streaming)
  -j, --job <name>       FlinkDeployment/job name
  --tail <n>             Log tail lines (default: 200)
  --yes                  Required for mutating commands
  -h, --help             Show help
USAGE
}

need_job() {
  [[ -n "$JOB" ]] || { echo "--job is required for this command" >&2; exit 1; }
}

need_yes() {
  if [[ "$YES" -ne 1 ]]; then
    echo "Mutating command requires --yes" >&2
    exit 1
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -n|--namespace)
        NAMESPACE="$2"
        shift 2
        ;;
      -j|--job)
        JOB="$2"
        shift 2
        ;;
      --tail)
        TAIL="$2"
        shift 2
        ;;
      --yes)
        YES=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "Unknown argument: $1" >&2
        exit 1
        ;;
    esac
  done
}

require_kube_api() {
  local context server err

  if kubectl get namespaces --request-timeout=7s >/dev/null 2>&1; then
    return 0
  fi

  context="$(kubectl config current-context 2>/dev/null || echo "<none>")"
  server="$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null || echo "<unknown>")"
  err="$(kubectl get namespaces --request-timeout=7s 2>&1 || true)"
  err="$(printf '%s\n' "$err" | grep -v 'memcache.go:' | tail -n 1 | sed 's/[[:space:]]\+/ /g')"

  cat >&2 <<EOF
Kubernetes API preflight failed.
Context: $context
Server: $server
Error: ${err:-unable to reach API}
Fix: start/select a reachable cluster, then retry.
EOF
  exit 2
}

cmd_status() {
  kubectl -n "$NAMESPACE" get flinkdeployments -o wide
  echo
  kubectl -n "$NAMESPACE" get pods -o wide | grep -E 'flink|taskmanager|jobmanager' || true
}

pods_for_job() {
  kubectl -n "$NAMESPACE" get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null | grep "$JOB" || true
}

cmd_logs() {
  need_job
  local pods
  pods="$(pods_for_job)"
  if [[ -z "$pods" ]]; then
    echo "No pods found for job pattern: $JOB" >&2
    exit 1
  fi

  while IFS= read -r pod; do
    [[ -z "$pod" ]] && continue
    echo "===== $pod ====="
    kubectl -n "$NAMESPACE" logs "$pod" --tail="$TAIL" || true
    echo
  done <<<"$pods"
}

cmd_restart() {
  need_job
  need_yes
  local current next
  current="$(kubectl -n "$NAMESPACE" get flinkdeployment "$JOB" -o jsonpath='{.spec.restartNonce}' 2>/dev/null || true)"
  current="${current:-0}"
  next=$((current + 1))
  kubectl -n "$NAMESPACE" patch flinkdeployment "$JOB" --type merge -p "{\"spec\":{\"restartNonce\":${next}}}"
  echo "restartNonce updated: ${current} -> ${next}"
}

cmd_suspend() {
  need_job
  need_yes
  kubectl -n "$NAMESPACE" patch flinkdeployment "$JOB" --type merge -p '{"spec":{"job":{"state":"suspended"}}}'
  echo "Job state set to suspended"
}

cmd_resume() {
  need_job
  need_yes
  kubectl -n "$NAMESPACE" patch flinkdeployment "$JOB" --type merge -p '{"spec":{"job":{"state":"running"}}}'
  echo "Job state set to running"
}

cmd_savepoint() {
  need_job
  need_yes
  local current next
  current="$(kubectl -n "$NAMESPACE" get flinkdeployment "$JOB" -o jsonpath='{.spec.job.savepointTriggerNonce}' 2>/dev/null || true)"
  current="${current:-0}"
  next=$((current + 1))
  kubectl -n "$NAMESPACE" patch flinkdeployment "$JOB" --type merge -p "{\"spec\":{\"job\":{\"savepointTriggerNonce\":${next}}}}"
  echo "savepointTriggerNonce updated: ${current} -> ${next}"
}

main() {
  command -v kubectl >/dev/null 2>&1 || { echo "kubectl is required" >&2; exit 1; }

  local command="${1:-}"
  [[ -n "$command" ]] || { usage; exit 1; }
  shift

  case "$command" in
    status|logs|restart|suspend|resume|savepoint)
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown command: $command" >&2
      usage
      exit 1
      ;;
  esac

  parse_args "$@"
  require_kube_api

  case "$command" in
    status) cmd_status ;;
    logs) cmd_logs ;;
    restart) cmd_restart ;;
    suspend) cmd_suspend ;;
    resume) cmd_resume ;;
    savepoint) cmd_savepoint ;;
  esac
}

main "$@"
