#!/usr/bin/env bash
set -euo pipefail

CONTEXT=""
OUT_DIR=""
ENSURE_METRICS_SERVER=0
CHECK_ONLY=0
WAIT_SECONDS=180
declare -a NAMESPACES=()

usage() {
  cat <<USAGE
Usage: $(basename "$0") [options]

Collect Kubernetes metrics snapshots and verify metrics.k8s.io readiness.

Options:
  --context <name>              Kube context override
  -n, --namespace <ns>          Namespace to show pod metrics (repeatable; default: all namespaces)
  --ensure-metrics-server       Install/upgrade metrics-server if metrics API is unavailable
  --check-only                  Verify metrics API only (no top/hpa snapshots)
  --wait <seconds>              Wait timeout for metrics API/top checks (default: 180)
  -o, --out <dir>               Output directory for captured files
  -h, --help                    Show help
USAGE
}

log() {
  printf '[k8s-metrics] %s\n' "$*"
}

KUBECTL_ARGS=()

k() {
  kubectl "${KUBECTL_ARGS[@]}" "$@"
}

run_capture() {
  local file="$1"
  shift
  {
    printf 'Command: kubectl %s %s\n\n' "${KUBECTL_ARGS[*]:-}" "$*"
    k "$@"
  } >"$file" 2>&1 || true
}

require_kube_api() {
  if k get namespaces --request-timeout=7s >/dev/null 2>&1; then
    return 0
  fi

  local context server err
  context="$(kubectl config current-context 2>/dev/null || echo "<none>")"
  server="$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null || echo "<unknown>")"
  err="$(k get namespaces --request-timeout=7s 2>&1 || true)"
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

metrics_api_available() {
  local available
  available="$(k get apiservice v1beta1.metrics.k8s.io -o json 2>/dev/null | jq -r '.status.conditions[]? | select(.type=="Available") | .status' || true)"
  [[ "$available" == "True" ]]
}

wait_for_metrics_api() {
  local deadline=$((SECONDS + WAIT_SECONDS))
  while (( SECONDS < deadline )); do
    if metrics_api_available; then
      return 0
    fi
    sleep 3
  done
  return 1
}

wait_for_top() {
  local deadline=$((SECONDS + WAIT_SECONDS))
  while (( SECONDS < deadline )); do
    if k top nodes >/dev/null 2>&1; then
      return 0
    fi
    sleep 3
  done
  return 1
}

ensure_metrics_server() {
  command -v helm >/dev/null 2>&1 || {
    echo "helm is required for --ensure-metrics-server" >&2
    return 1
  }

  log "Installing/upgrading metrics-server in kube-system..."
  helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server --force-update >/dev/null
  helm repo update >/dev/null

  helm upgrade --install metrics-server metrics-server/metrics-server \
    -n kube-system \
    --wait \
    --timeout 8m \
    --set-string 'args[0]=--kubelet-insecure-tls' \
    --set-string 'args[1]=--kubelet-preferred-address-types=InternalIP\,Hostname\,InternalDNS\,ExternalDNS\,ExternalIP' >/dev/null

  log "Waiting for metrics.k8s.io APIService..."
  if ! wait_for_metrics_api; then
    log "metrics.k8s.io APIService did not become Available in ${WAIT_SECONDS}s"
    return 1
  fi

  log "Waiting for kubectl top readiness..."
  if ! wait_for_top; then
    log "kubectl top is not ready after metrics-server installation"
    return 1
  fi

  log "metrics-server is ready."
  return 0
}

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --context)
        CONTEXT="$2"
        shift 2
        ;;
      -n|--namespace)
        NAMESPACES+=("$2")
        shift 2
        ;;
      --ensure-metrics-server)
        ENSURE_METRICS_SERVER=1
        shift
        ;;
      --check-only)
        CHECK_ONLY=1
        shift
        ;;
      --wait)
        WAIT_SECONDS="$2"
        shift 2
        ;;
      -o|--out)
        OUT_DIR="$2"
        shift 2
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

  command -v kubectl >/dev/null 2>&1 || { echo "kubectl is required" >&2; exit 1; }
  command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }

  if [[ -n "$CONTEXT" ]]; then
    KUBECTL_ARGS+=(--context "$CONTEXT")
  fi

  require_kube_api

  if [[ -n "$OUT_DIR" ]]; then
    mkdir -p "$OUT_DIR"
  fi

  if ! metrics_api_available; then
    log "metrics.k8s.io APIService is unavailable."
    if [[ "$ENSURE_METRICS_SERVER" -eq 1 ]]; then
      ensure_metrics_server
    else
      log "Re-run with --ensure-metrics-server to auto-install metrics-server."
      exit 1
    fi
  else
    log "metrics.k8s.io APIService is available."
  fi

  if [[ "$CHECK_ONLY" -eq 1 ]]; then
    if [[ -n "$OUT_DIR" ]]; then
      run_capture "$OUT_DIR/apiservice.txt" get apiservice v1beta1.metrics.k8s.io -o wide
    else
      k get apiservice v1beta1.metrics.k8s.io -o wide
    fi
    exit 0
  fi

  if [[ -n "$OUT_DIR" ]]; then
    run_capture "$OUT_DIR/apiservice.txt" get apiservice v1beta1.metrics.k8s.io -o wide
    run_capture "$OUT_DIR/top-nodes.txt" top nodes
    run_capture "$OUT_DIR/hpa.txt" get hpa -A
    run_capture "$OUT_DIR/events-hpa-metrics.txt" get events -A --sort-by=.lastTimestamp
  else
    k get apiservice v1beta1.metrics.k8s.io -o wide
    echo
    k top nodes
    echo
    k get hpa -A
    echo
    k get events -A --sort-by=.lastTimestamp | grep -E 'FailedGetResourceMetric|FailedComputeMetricsReplicas|pods.metrics.k8s.io|horizontalpodautoscaler' || true
  fi

  if [[ "${#NAMESPACES[@]}" -eq 0 ]]; then
    if [[ -n "$OUT_DIR" ]]; then
      run_capture "$OUT_DIR/top-pods-all.txt" top pods -A
    else
      echo
      k top pods -A
    fi
  else
    for ns in "${NAMESPACES[@]}"; do
      if [[ -n "$OUT_DIR" ]]; then
        run_capture "$OUT_DIR/top-pods-${ns}.txt" top pods -n "$ns"
      else
        echo
        log "Namespace: $ns"
        k top pods -n "$ns"
      fi
    done
  fi

  if [[ -n "$OUT_DIR" ]]; then
    log "Metrics snapshot written to $OUT_DIR"
  fi
}

main "$@"
