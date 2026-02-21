#!/usr/bin/env bash
set -euo pipefail

STRICT_OPTIONAL=0
DEFAULT_RUNTIME_BIN="/home/shkas/trading-agent-runtime/bin"
DEFAULT_RAAZ_RUNTIME_BIN="/home/shkas/projects/raaz/.runtime/bin"
LOCAL_BIN_DIR="$HOME/.local/bin"

export PATH="${DEFAULT_RUNTIME_BIN}:${DEFAULT_RAAZ_RUNTIME_BIN}:${LOCAL_BIN_DIR}:$PATH"

usage() {
  cat <<USAGE
Usage: $(basename "$0") [--strict-optional]

Validates trading-platform CLI baseline and reports drift.

Options:
  --strict-optional  Treat optional tool misses as failures.
USAGE
}

version_of() {
  local cmd="$1"
  case "$cmd" in
    tpdeploy)
      command -v tpdeploy >/dev/null 2>&1 || return 1
      echo "installed"
      ;;
    agentctl)
      agentctl --help 2>/dev/null | head -n1 || echo "installed"
      ;;
    trpg)
      if [[ -L "$(command -v trpg 2>/dev/null || true)" ]]; then
        echo "linked"
      else
        echo "installed"
      fi
      ;;
    kubectl)
      kubectl version --client --output=yaml 2>/dev/null | awk '/gitVersion:/ {print $2; exit}' || true
      ;;
    helm)
      helm version --short 2>/dev/null || true
      ;;
    kind)
      kind version 2>/dev/null || true
      ;;
    docker)
      docker version --format '{{.Client.Version}}' 2>/dev/null || true
      ;;
    jq)
      jq --version 2>/dev/null || true
      ;;
    yq)
      yq --version 2>/dev/null | head -n1 || true
      ;;
    rg)
      rg --version 2>/dev/null | head -n1 || true
      ;;
    stern)
      stern --version 2>/dev/null | head -n1 || true
      ;;
    k9s)
      k9s version --short 2>/dev/null | head -n1 || k9s version 2>/dev/null | head -n1 || true
      ;;
    kubectx)
      echo "installed"
      ;;
    kubens)
      echo "installed"
      ;;
    kcat)
      echo "installed"
      ;;
    *)
      echo "installed"
      ;;
  esac
}

check_bin() {
  local tier="$1"
  local cmd="$2"
  local failures_ref="$3"

  local status path ver
  if command -v "$cmd" >/dev/null 2>&1; then
    status="OK"
    path="$(command -v "$cmd")"
    ver="$(version_of "$cmd")"
    ver="${ver:-n/a}"
  else
    status="MISS"
    path="-"
    ver="-"
    if [[ "$tier" == "required" || ("$tier" == "optional" && "$STRICT_OPTIONAL" -eq 1) ]]; then
      eval "$failures_ref=$(( $failures_ref + 1 ))"
    fi
  fi

  printf '%-9s %-10s %-12s %-45s %s\n' "$tier" "$cmd" "$status" "$path" "$ver"
}

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --strict-optional)
        STRICT_OPTIONAL=1
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

  local required=(tpdeploy agentctl trpg kubectl helm kind docker jq yq rg stern)
  local optional=(k9s kubectx kubens kcat)
  local failures=0

  printf '%-9s %-10s %-12s %-45s %s\n' "tier" "tool" "status" "path" "version"
  printf '%-9s %-10s %-12s %-45s %s\n' "--------" "----------" "------------" "---------------------------------------------" "-------------------------"

  local tool
  for tool in "${required[@]}"; do
    check_bin "required" "$tool" failures
  done

  for tool in "${optional[@]}"; do
    check_bin "optional" "$tool" failures
  done

  local yq_line
  yq_line="$(yq --version 2>/dev/null | head -n1 || true)"
  if [[ -z "$yq_line" || (!( "$yq_line" =~ mikefarah/yq ) && !( "$yq_line" =~ version\ v4\. )) ]]; then
    echo "[doctor][fail] yq is not mikefarah/yq v4; detected: ${yq_line:-missing}" >&2
    failures=$((failures + 1))
  else
    echo "[doctor][ok] yq variant: $yq_line"
  fi

  if helm plugin list 2>/dev/null | awk 'NR>1 {print $1}' | grep -qx 'diff'; then
    echo "[doctor][ok] helm diff plugin installed"
  else
    echo "[doctor][fail] helm diff plugin is missing" >&2
    failures=$((failures + 1))
  fi

  if [[ "$failures" -gt 0 ]]; then
    echo "[doctor] baseline check failed with ${failures} issue(s)" >&2
    exit 1
  fi

  echo "[doctor] baseline check passed"
}

main "$@"
