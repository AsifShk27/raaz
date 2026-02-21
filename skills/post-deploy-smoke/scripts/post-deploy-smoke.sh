#!/usr/bin/env bash
set -euo pipefail

TIMEOUT_SECONDS=180
OUTPUT_DIR="artifacts/post-deploy-smoke-$(date +%Y%m%d-%H%M%S)"
STRICT=1

declare -a NAMESPACES=(streaming data-services trading-platform-apps monitoring)
declare -a PROBES=()

usage() {
  cat <<USAGE
Usage: $(basename "$0") [options]

Run post-deploy smoke checks across namespaces.

Options:
  -n, --namespace <ns>      Namespace to check (repeatable). Overrides defaults.
  --timeout <seconds>       Rollout timeout per workload (default: 180)
  --probe <name=url>        HTTP probe endpoint (repeatable)
  --out <dir>               Output directory
  --non-strict              Do not fail process on smoke failures
  -h, --help                Show help
USAGE
}

log() {
  printf '[post-deploy-smoke] %s\n' "$*"
}

run_capture() {
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

reset_namespaces=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--namespace)
      if [[ "$reset_namespaces" -eq 0 ]]; then
        NAMESPACES=()
        reset_namespaces=1
      fi
      NAMESPACES+=("$2")
      shift 2
      ;;
    --timeout)
      TIMEOUT_SECONDS="$2"
      shift 2
      ;;
    --probe)
      PROBES+=("$2")
      shift 2
      ;;
    --out)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --non-strict)
      STRICT=0
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

command -v kubectl >/dev/null 2>&1 || { echo "kubectl is required" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "curl is required" >&2; exit 1; }
require_kube_api

mkdir -p "$OUTPUT_DIR"

failures=0

for ns in "${NAMESPACES[@]}"; do
  mkdir -p "$OUTPUT_DIR/$ns"
  log "Checking namespace: $ns"

  run_capture "$OUTPUT_DIR/$ns/pods.txt" kubectl -n "$ns" get pods -o wide
  run_capture "$OUTPUT_DIR/$ns/events.txt" kubectl -n "$ns" get events --sort-by=.lastTimestamp

  # Rollout status for deployments
  while IFS= read -r deploy; do
    [[ -z "$deploy" ]] && continue
    local_file="$OUTPUT_DIR/$ns/rollout-deploy-${deploy}.txt"
    if ! kubectl -n "$ns" rollout status "deployment/$deploy" --timeout="${TIMEOUT_SECONDS}s" >"$local_file" 2>&1; then
      failures=$((failures + 1))
    fi
  done < <(kubectl -n "$ns" get deployments -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)

  # Rollout status for statefulsets
  while IFS= read -r sts; do
    [[ -z "$sts" ]] && continue
    local_file="$OUTPUT_DIR/$ns/rollout-sts-${sts}.txt"
    if ! kubectl -n "$ns" rollout status "statefulset/$sts" --timeout="${TIMEOUT_SECONDS}s" >"$local_file" 2>&1; then
      failures=$((failures + 1))
    fi
  done < <(kubectl -n "$ns" get statefulsets -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)

  # Failing pods detection
  if ! kubectl -n "$ns" get pods -o json 2>/dev/null | jq -e '
      .items[]?
      | . as $pod
      | (($pod.status.containerStatuses // []) + ($pod.status.initContainerStatuses // [])) as $statuses
      | ($pod.status.phase // "") as $phase
      | ($statuses | any(
          (.ready == false)
          or ((.state.waiting.reason // "") | test("CrashLoopBackOff|ImagePullBackOff|ErrImagePull|CreateContainerConfigError|RunContainerError"))
        )) as $bad
      | select($phase == "Failed" or $phase == "Pending" or $phase == "Unknown" or $bad)
      | .metadata.name
    ' >"$OUTPUT_DIR/$ns/failing-pods.txt"; then
    : >"$OUTPUT_DIR/$ns/failing-pods.txt"
  fi

  if [[ -s "$OUTPUT_DIR/$ns/failing-pods.txt" ]]; then
    failures=$((failures + 1))
  fi

done

probe_failures=0
if [[ "${#PROBES[@]}" -gt 0 ]]; then
  mkdir -p "$OUTPUT_DIR/probes"
  for probe in "${PROBES[@]}"; do
    name="${probe%%=*}"
    url="${probe#*=}"
    out="$OUTPUT_DIR/probes/${name}.txt"

    code="$(curl -sS -o "$OUTPUT_DIR/probes/${name}.body" -w '%{http_code}' --max-time 15 "$url" || true)"
    {
      echo "name=$name"
      echo "url=$url"
      echo "http_code=$code"
    } >"$out"

    if [[ ! "$code" =~ ^2|3 ]]; then
      probe_failures=$((probe_failures + 1))
    fi
  done
fi

failures=$((failures + probe_failures))

cat >"$OUTPUT_DIR/summary.md" <<SUMMARY
# Post Deploy Smoke Summary

- Namespaces checked: ${NAMESPACES[*]}
- Rollout timeout: ${TIMEOUT_SECONDS}s
- HTTP probes: ${#PROBES[@]}
- Probe failures: ${probe_failures}
- Total failure signals: ${failures}
- Strict mode: $( [[ "$STRICT" -eq 1 ]] && echo yes || echo no )
SUMMARY

if [[ "$STRICT" -eq 1 && "$failures" -gt 0 ]]; then
  log "Smoke failed with ${failures} issue(s). See $OUTPUT_DIR/summary.md"
  exit 1
fi

log "Smoke completed. Summary: $OUTPUT_DIR/summary.md"
