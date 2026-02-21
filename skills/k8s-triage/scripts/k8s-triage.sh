#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="all"
SELECTOR=""
TAIL_LINES=200
INCLUDE_LOGS=1
OUTPUT_DIR="artifacts/k8s-triage-$(date +%Y%m%d-%H%M%S)"

usage() {
  cat <<USAGE
Usage: $(basename "$0") [options]

Collect Kubernetes triage bundle for failing workloads.

Options:
  -n, --namespace <ns>    Namespace (default: all)
  -l, --selector <label>  Label selector (optional)
  --tail <n>              Log tail lines per container (default: 200)
  --no-logs               Skip log capture
  -o, --output <dir>      Output directory
  -h, --help              Show help
USAGE
}

log() {
  printf '[k8s-triage] %s\n' "$*"
}

run_to_file() {
  local file="$1"
  shift
  {
    printf 'Command: %s\n\n' "$*"
    "$@"
  } >"$file" 2>&1 || true
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

pod_query_args() {
  local args=(get pods)
  if [[ "$NAMESPACE" == "all" ]]; then
    args+=( -A )
  else
    args+=( -n "$NAMESPACE" )
  fi
  if [[ -n "$SELECTOR" ]]; then
    args+=( -l "$SELECTOR" )
  fi
  printf '%s\n' "${args[*]}"
}

capture_rollouts() {
  if [[ "$NAMESPACE" == "all" ]]; then
    return 0
  fi

  mkdir -p "$OUTPUT_DIR/rollouts"

  local deploy
  while IFS= read -r deploy; do
    [[ -z "$deploy" ]] && continue
    run_to_file "$OUTPUT_DIR/rollouts/deploy-${deploy}.txt" \
      kubectl -n "$NAMESPACE" rollout status "deployment/${deploy}" --timeout=180s
  done < <(kubectl -n "$NAMESPACE" get deployments -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)

  local sts
  while IFS= read -r sts; do
    [[ -z "$sts" ]] && continue
    run_to_file "$OUTPUT_DIR/rollouts/sts-${sts}.txt" \
      kubectl -n "$NAMESPACE" rollout status "statefulset/${sts}" --timeout=180s
  done < <(kubectl -n "$NAMESPACE" get statefulsets -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)
}

collect_failing_pods() {
  local pods_json
  local failing_file="$OUTPUT_DIR/failing-pods.tsv"

  if [[ "$NAMESPACE" == "all" ]]; then
    if [[ -n "$SELECTOR" ]]; then
      pods_json="$(kubectl get pods -A -l "$SELECTOR" -o json 2>/dev/null || true)"
    else
      pods_json="$(kubectl get pods -A -o json 2>/dev/null || true)"
    fi
  else
    if [[ -n "$SELECTOR" ]]; then
      pods_json="$(kubectl -n "$NAMESPACE" get pods -l "$SELECTOR" -o json 2>/dev/null || true)"
    else
      pods_json="$(kubectl -n "$NAMESPACE" get pods -o json 2>/dev/null || true)"
    fi
  fi

  if [[ -z "$pods_json" ]]; then
    : >"$failing_file"
    return 0
  fi

  jq -r '
    .items[]?
    | . as $pod
    | (($pod.status.containerStatuses // []) + ($pod.status.initContainerStatuses // [])) as $statuses
    | ($pod.status.phase // "") as $phase
    | ($statuses | any(
        (.restartCount // 0) > 0
        or ((.state.waiting.reason // "") | test("CrashLoopBackOff|ImagePullBackOff|ErrImagePull|CreateContainerConfigError|RunContainerError"))
      )) as $hasIssue
    | select($phase == "Pending" or $phase == "Failed" or $phase == "Unknown" or $hasIssue)
    | [.metadata.namespace, .metadata.name] | @tsv
  ' <<<"$pods_json" >"$failing_file"
}

capture_pod_artifacts() {
  mkdir -p "$OUTPUT_DIR/pods"

  while IFS=$'\t' read -r ns pod; do
    [[ -z "$ns" || -z "$pod" ]] && continue

    local pod_prefix="$OUTPUT_DIR/pods/${ns}-${pod}"

    run_to_file "${pod_prefix}-describe.txt" kubectl -n "$ns" describe pod "$pod"

    if [[ "$INCLUDE_LOGS" -eq 0 ]]; then
      continue
    fi

    local containers
    containers="$(kubectl -n "$ns" get pod "$pod" -o jsonpath='{range .spec.initContainers[*]}{.name}{"\n"}{end}{range .spec.containers[*]}{.name}{"\n"}{end}' 2>/dev/null || true)"

    while IFS= read -r container; do
      [[ -z "$container" ]] && continue
      run_to_file "${pod_prefix}-logs-${container}.txt" \
        kubectl -n "$ns" logs "$pod" -c "$container" --tail="$TAIL_LINES"
      run_to_file "${pod_prefix}-logs-prev-${container}.txt" \
        kubectl -n "$ns" logs "$pod" -c "$container" --previous --tail="$TAIL_LINES"
    done <<<"$containers"

  done <"$OUTPUT_DIR/failing-pods.tsv"
}

write_summary() {
  local pod_count=0 failing_count=0

  if [[ "$NAMESPACE" == "all" ]]; then
    pod_count="$(kubectl get pods -A --no-headers 2>/dev/null | wc -l | awk '{print $1}')"
  else
    pod_count="$(kubectl -n "$NAMESPACE" get pods --no-headers 2>/dev/null | wc -l | awk '{print $1}')"
  fi

  if [[ -f "$OUTPUT_DIR/failing-pods.tsv" ]]; then
    failing_count="$(wc -l <"$OUTPUT_DIR/failing-pods.tsv" | awk '{print $1}')"
  fi

  cat >"$OUTPUT_DIR/summary.md" <<SUMMARY
# Kubernetes Triage Summary

- Namespace: ${NAMESPACE}
- Selector: ${SELECTOR:-<none>}
- Total pods inspected: ${pod_count}
- Failing or unstable pods: ${failing_count}
- Logs captured: $( [[ "$INCLUDE_LOGS" -eq 1 ]] && echo yes || echo no )

## Bundle Contents

- \
`cluster/\`:
  - current context, cluster info, namespaces, nodes
- \
`workloads/\`:
  - pods and events snapshots
- \
`failing-pods.tsv\`:
  - namespace/pod list flagged by phase/restarts/waiting reasons
- \
`pods/\`:
  - per-pod describe and container logs
- \
`rollouts/\`:
  - rollout status (namespace mode only)
SUMMARY
}

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -n|--namespace)
        NAMESPACE="$2"
        shift 2
        ;;
      -l|--selector)
        SELECTOR="$2"
        shift 2
        ;;
      --tail)
        TAIL_LINES="$2"
        shift 2
        ;;
      --no-logs)
        INCLUDE_LOGS=0
        shift
        ;;
      -o|--output)
        OUTPUT_DIR="$2"
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
  require_kube_api

  mkdir -p "$OUTPUT_DIR/cluster" "$OUTPUT_DIR/workloads"

  log "Writing triage bundle to $OUTPUT_DIR"

  run_to_file "$OUTPUT_DIR/cluster/current-context.txt" kubectl config current-context
  run_to_file "$OUTPUT_DIR/cluster/cluster-info.txt" kubectl cluster-info
  run_to_file "$OUTPUT_DIR/cluster/namespaces.txt" kubectl get namespaces -o wide
  run_to_file "$OUTPUT_DIR/cluster/nodes.txt" kubectl get nodes -o wide

  if [[ "$NAMESPACE" == "all" ]]; then
    if [[ -n "$SELECTOR" ]]; then
      run_to_file "$OUTPUT_DIR/workloads/pods.txt" kubectl get pods -A -l "$SELECTOR" -o wide
      run_to_file "$OUTPUT_DIR/workloads/events.txt" kubectl get events -A -l "$SELECTOR" --sort-by=.lastTimestamp
    else
      run_to_file "$OUTPUT_DIR/workloads/pods.txt" kubectl get pods -A -o wide
      run_to_file "$OUTPUT_DIR/workloads/events.txt" kubectl get events -A --sort-by=.lastTimestamp
    fi
  else
    if [[ -n "$SELECTOR" ]]; then
      run_to_file "$OUTPUT_DIR/workloads/pods.txt" kubectl -n "$NAMESPACE" get pods -l "$SELECTOR" -o wide
      run_to_file "$OUTPUT_DIR/workloads/events.txt" kubectl -n "$NAMESPACE" get events -l "$SELECTOR" --sort-by=.lastTimestamp
    else
      run_to_file "$OUTPUT_DIR/workloads/pods.txt" kubectl -n "$NAMESPACE" get pods -o wide
      run_to_file "$OUTPUT_DIR/workloads/events.txt" kubectl -n "$NAMESPACE" get events --sort-by=.lastTimestamp
    fi
  fi

  collect_failing_pods
  capture_pod_artifacts
  capture_rollouts
  write_summary

  log "Triage bundle ready: $OUTPUT_DIR"
}

main "$@"
