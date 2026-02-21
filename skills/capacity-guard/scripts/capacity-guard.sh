#!/usr/bin/env bash
set -euo pipefail

OUTPUT_FORMAT="text"

usage() {
  cat <<USAGE
Usage: $(basename "$0") [--json]

Compute host/runtime capacity signals and recommend safe max-workers
for trading-platform install/rebuild operations.

Options:
  --json      Emit JSON output
  -h, --help  Show help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json)
      OUTPUT_FORMAT="json"
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

cpu_count="$(nproc 2>/dev/null || echo 1)"
load_1m="$(awk '{print $1}' /proc/loadavg 2>/dev/null || echo 0)"
mem_available_kb="$(awk '/MemAvailable/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"
mem_available_gb="$(awk -v kb="$mem_available_kb" 'BEGIN {printf "%.1f", kb/1024/1024}')"

docker_running=0
if command -v docker >/dev/null 2>&1; then
  docker_running="$(docker ps --format '{{.ID}}' 2>/dev/null | wc -l | awk '{print $1}' || true)"
  [[ "$docker_running" =~ ^[0-9]+$ ]] || docker_running=0
fi

k8s_pods=0
if command -v kubectl >/dev/null 2>&1; then
  k8s_pods="$(kubectl get pods -A --no-headers 2>/dev/null | wc -l | awk '{print $1}' || true)"
  [[ "$k8s_pods" =~ ^[0-9]+$ ]] || k8s_pods=0
fi

wsl_swap="unknown"
wsl_cfg="/mnt/c/Users/shkas/.wslconfig"
if [[ -f "$wsl_cfg" ]]; then
  wsl_swap_line="$(awk -F= 'tolower($1) ~ /^swap$/ {gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}' "$wsl_cfg" | tail -n1 || true)"
  if [[ -n "$wsl_swap_line" ]]; then
    wsl_swap="$wsl_swap_line"
  fi
fi

recommended=3
rationale=()

if awk -v m="$mem_available_gb" 'BEGIN {exit !(m < 8)}'; then
  recommended=1
  rationale+=("mem_available_lt_8gb")
elif awk -v m="$mem_available_gb" 'BEGIN {exit !(m < 16)}'; then
  recommended=2
  rationale+=("mem_available_lt_16gb")
elif awk -v m="$mem_available_gb" 'BEGIN {exit !(m < 32)}'; then
  recommended=3
  rationale+=("mem_available_lt_32gb")
else
  recommended=4
  rationale+=("mem_available_ge_32gb")
fi

if awk -v l="$load_1m" -v c="$cpu_count" 'BEGIN {exit !(l > (c * 0.8))}'; then
  recommended=$((recommended - 1))
  rationale+=("high_cpu_load")
fi

if [[ "$docker_running" -gt 60 ]]; then
  recommended=$((recommended - 1))
  rationale+=("many_running_docker_containers")
fi

if [[ "$k8s_pods" -gt 250 ]]; then
  recommended=$((recommended - 1))
  rationale+=("high_k8s_pod_count")
fi

if [[ "$recommended" -lt 1 ]]; then
  recommended=1
fi
if [[ "$recommended" -gt 6 ]]; then
  recommended=6
fi

if [[ "$OUTPUT_FORMAT" == "json" ]]; then
  command -v jq >/dev/null 2>&1 || { echo "jq is required for --json output" >&2; exit 1; }
  jq -n \
    --arg cpuCount "$cpu_count" \
    --arg load1m "$load_1m" \
    --arg memAvailableGb "$mem_available_gb" \
    --arg dockerRunning "$docker_running" \
    --arg k8sPods "$k8s_pods" \
    --arg wslSwap "$wsl_swap" \
    --argjson recommendedMaxWorkers "$recommended" \
    --arg rationale "${rationale[*]:-default-policy}" \
    '{
      cpuCount: ($cpuCount|tonumber),
      load1m: ($load1m|tonumber),
      memAvailableGb: ($memAvailableGb|tonumber),
      dockerRunning: ($dockerRunning|tonumber),
      k8sPods: ($k8sPods|tonumber),
      wslSwap: $wslSwap,
      recommendedMaxWorkers: $recommendedMaxWorkers,
      rationale: ($rationale | split(" "))
    }'
  exit 0
fi

cat <<TEXT
Capacity Guard Report
---------------------
CPU count:               ${cpu_count}
Load (1m):               ${load_1m}
Mem available (GiB):     ${mem_available_gb}
Running Docker ctrs:     ${docker_running}
K8s pods total:          ${k8s_pods}
WSL swap config:         ${wsl_swap}

Recommended max-workers: ${recommended}
Rationale:               ${rationale[*]:-default-policy}

Suggested commands:
- tpdeploy install --max-workers ${recommended} --no-confirm
- tpdeploy rebuild-all <services...> --max-workers ${recommended}
TEXT
