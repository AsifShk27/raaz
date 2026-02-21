#!/usr/bin/env bash
set -euo pipefail

RELEASE=""
CHART=""
NAMESPACE="default"
OUT_DIR="artifacts/helm-release-guard-$(date +%Y%m%d-%H%M%S)"
FAIL_ON_MUTABLE_TAGS=1

declare -a VALUES_FILES=()
declare -a SET_ARGS=()

usage() {
  cat <<USAGE
Usage: $(basename "$0") --release <name> --chart <path> [options]

Run Helm safety checks before upgrade.

Options:
  --release <name>         Helm release name (required)
  --chart <path>           Helm chart directory (required)
  --namespace <ns>         Namespace (default: default)
  --values <file>          Values file (repeatable)
  --set <key=value>        Set override (repeatable)
  --out <dir>              Output directory
  --allow-mutable-tags     Do not fail on mutable image tags
  -h, --help               Show help
USAGE
}

log() {
  printf '[helm-release-guard] %s\n' "$*"
}

run_capture() {
  local file="$1"
  shift
  {
    printf 'Command: %s\n\n' "$*"
    "$@"
  } >"$file" 2>&1
}

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --release)
        RELEASE="$2"
        shift 2
        ;;
      --chart)
        CHART="$2"
        shift 2
        ;;
      --namespace)
        NAMESPACE="$2"
        shift 2
        ;;
      --values)
        VALUES_FILES+=("$2")
        shift 2
        ;;
      --set)
        SET_ARGS+=("$2")
        shift 2
        ;;
      --out)
        OUT_DIR="$2"
        shift 2
        ;;
      --allow-mutable-tags)
        FAIL_ON_MUTABLE_TAGS=0
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

  [[ -n "$RELEASE" ]] || { echo "--release is required" >&2; exit 1; }
  [[ -n "$CHART" ]] || { echo "--chart is required" >&2; exit 1; }

  command -v helm >/dev/null 2>&1 || { echo "helm is required" >&2; exit 1; }
  command -v rg >/dev/null 2>&1 || { echo "rg is required" >&2; exit 1; }

  if ! helm plugin list 2>/dev/null | awk 'NR>1 {print $1}' | grep -qx 'diff'; then
    echo "helm diff plugin is required" >&2
    exit 1
  fi

  mkdir -p "$OUT_DIR"

  local -a value_flags=()
  local vf
  for vf in "${VALUES_FILES[@]}"; do
    value_flags+=( -f "$vf" )
  done

  local -a set_flags=()
  local s
  for s in "${SET_ARGS[@]}"; do
    set_flags+=( --set "$s" )
  done

  local lint_ok=1 template_ok=1 diff_ok=1

  if ! run_capture "$OUT_DIR/lint.txt" helm lint "$CHART" "${value_flags[@]}"; then
    lint_ok=0
  fi

  local rendered="$OUT_DIR/rendered.yaml"
  if ! run_capture "$OUT_DIR/template.txt" helm template "$RELEASE" "$CHART" -n "$NAMESPACE" "${value_flags[@]}" "${set_flags[@]}"; then
    template_ok=0
  else
    helm template "$RELEASE" "$CHART" -n "$NAMESPACE" "${value_flags[@]}" "${set_flags[@]}" >"$rendered"
  fi

  if ! run_capture "$OUT_DIR/diff.txt" helm diff upgrade "$RELEASE" "$CHART" -n "$NAMESPACE" --allow-unreleased "${value_flags[@]}" "${set_flags[@]}"; then
    diff_ok=0
  fi

  local mutable_tags_file="$OUT_DIR/mutable-image-tags.txt"
  : >"$mutable_tags_file"
  local mutable_count=0
  if [[ -s "$rendered" ]]; then
    rg -n 'image:\s*[^[:space:]]+:(latest|main|master)$' "$rendered" >"$mutable_tags_file" || true
    if [[ -s "$mutable_tags_file" ]]; then
      mutable_count="$(wc -l <"$mutable_tags_file" | awk '{print $1}')"
    fi
  fi

  cat >"$OUT_DIR/summary.md" <<SUMMARY
# Helm Release Guard Summary

- Release: ${RELEASE}
- Chart: ${CHART}
- Namespace: ${NAMESPACE}
- Lint: $( [[ "$lint_ok" -eq 1 ]] && echo PASS || echo FAIL )
- Template: $( [[ "$template_ok" -eq 1 ]] && echo PASS || echo FAIL )
- Diff: $( [[ "$diff_ok" -eq 1 ]] && echo PASS || echo FAIL )
- Mutable image tags found: ${mutable_count}

## Artifacts

- \
`lint.txt\`
- \
`template.txt\`
- \
`rendered.yaml\`
- \
`diff.txt\`
- \
`mutable-image-tags.txt\`
SUMMARY

  local failures=0
  [[ "$lint_ok" -eq 1 ]] || failures=$((failures + 1))
  [[ "$template_ok" -eq 1 ]] || failures=$((failures + 1))
  [[ "$diff_ok" -eq 1 ]] || failures=$((failures + 1))

  if [[ "$FAIL_ON_MUTABLE_TAGS" -eq 1 && "$mutable_count" -gt 0 ]]; then
    failures=$((failures + 1))
  fi

  if [[ "$failures" -gt 0 ]]; then
    log "Guard failed with ${failures} issue(s). See $OUT_DIR/summary.md"
    exit 1
  fi

  log "Guard passed. Summary: $OUT_DIR/summary.md"
}

main "$@"
