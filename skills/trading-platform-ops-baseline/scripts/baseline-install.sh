#!/usr/bin/env bash
set -euo pipefail

DEFAULT_RUNTIME_BIN="/home/shkas/trading-agent-runtime/bin"
DEFAULT_RAAZ_RUNTIME_BIN="/home/shkas/projects/raaz/.runtime/bin"
LOCAL_BIN_DIR="${LOCAL_BIN_DIR:-$HOME/.local/bin}"

if [[ -n "${BIN_DIR:-}" ]]; then
  INSTALL_BIN_DIR="$BIN_DIR"
elif [[ -d "$DEFAULT_RUNTIME_BIN" ]]; then
  INSTALL_BIN_DIR="$DEFAULT_RUNTIME_BIN"
elif [[ -d "$DEFAULT_RAAZ_RUNTIME_BIN" ]]; then
  INSTALL_BIN_DIR="$DEFAULT_RAAZ_RUNTIME_BIN"
else
  INSTALL_BIN_DIR="$LOCAL_BIN_DIR"
fi
KCAT_IMAGE="${KCAT_IMAGE:-edenhill/kcat:1.7.0}"
TRPG_SOURCE="/home/shkas/projects/raaz/skills/trading-runtime-postgres/scripts/trpg"
INSTALL_OPTIONAL=1

usage() {
  cat <<USAGE
Usage: $(basename "$0") [--required-only]

Installs/repairs trading-platform CLI baseline in user space.

Options:
  --required-only  Install required tools only (skip optional tools).
USAGE
}

log() {
  printf '[baseline-install] %s\n' "$*"
}

warn() {
  printf '[baseline-install][warn] %s\n' "$*" >&2
}

fail() {
  printf '[baseline-install][error] %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

latest_asset_url() {
  local repo="$1"
  local regex="$2"

  local release_json
  release_json="$(curl -fsSL "https://api.github.com/repos/${repo}/releases/latest")"

  local asset_url
  asset_url="$(jq -r --arg re "$regex" '.assets[]? | select(.name | test($re)) | .browser_download_url' <<<"$release_json" | head -n1)"

  if [[ -z "$asset_url" || "$asset_url" == "null" ]]; then
    fail "Unable to find release asset for ${repo} matching regex: ${regex}"
  fi

  printf '%s\n' "$asset_url"
}

link_local_bin() {
  local target_name="$1"
  mkdir -p "$LOCAL_BIN_DIR"

  if [[ "$INSTALL_BIN_DIR" == "$LOCAL_BIN_DIR" ]]; then
    return 0
  fi

  ln -sfn "$INSTALL_BIN_DIR/$target_name" "$LOCAL_BIN_DIR/$target_name"
}

install_binary_from_tar() {
  local repo="$1"
  local asset_regex="$2"
  local binary_name="$3"
  local target_name="${4:-$3}"

  local url
  url="$(latest_asset_url "$repo" "$asset_regex")"

  local archive tmp_dir src_path
  archive="$(mktemp)"
  tmp_dir="$(mktemp -d)"

  curl -fsSL "$url" -o "$archive"
  tar -xzf "$archive" -C "$tmp_dir"

  src_path="$(find "$tmp_dir" -type f -name "$binary_name" | head -n1 || true)"
  if [[ -z "$src_path" ]]; then
    rm -rf "$archive" "$tmp_dir"
    fail "Could not locate binary ${binary_name} inside asset ${url}"
  fi

  install -m 0755 "$src_path" "$INSTALL_BIN_DIR/$target_name"
  link_local_bin "$target_name"
  rm -rf "$archive" "$tmp_dir"
  log "Installed ${target_name} from ${repo}"
}

install_direct_binary() {
  local repo="$1"
  local asset_regex="$2"
  local target_name="$3"

  local url
  url="$(latest_asset_url "$repo" "$asset_regex")"

  curl -fsSL "$url" -o "$INSTALL_BIN_DIR/$target_name"
  chmod 0755 "$INSTALL_BIN_DIR/$target_name"
  link_local_bin "$target_name"
  log "Installed ${target_name} from ${repo}"
}

ensure_trpg() {
  if [[ ! -x "$TRPG_SOURCE" ]]; then
    fail "trpg source script not found at ${TRPG_SOURCE}"
  fi

  ln -sfn "$TRPG_SOURCE" "$INSTALL_BIN_DIR/trpg"
  link_local_bin "trpg"
  chmod 0755 "$TRPG_SOURCE"
  log "Installed trpg wrapper link"
}

ensure_yq_v4() {
  local yq_ok=0
  if command -v yq >/dev/null 2>&1; then
    local version_line
    version_line="$(yq --version 2>&1 | head -n1 || true)"
    if [[ "$version_line" =~ mikefarah/yq ]] || [[ "$version_line" =~ version\ v4\. ]]; then
      yq_ok=1
    fi
  fi

  if [[ "$yq_ok" -eq 1 ]]; then
    log "yq v4 already available"
    return 0
  fi

  install_direct_binary "mikefarah/yq" '^yq_linux_amd64$' "yq"
}

ensure_stern() {
  if command -v stern >/dev/null 2>&1; then
    log "stern already available"
    return 0
  fi

  install_binary_from_tar "stern/stern" 'stern_.*_linux_amd64\.tar\.gz$' "stern"
}

ensure_k9s() {
  if command -v k9s >/dev/null 2>&1; then
    log "k9s already available"
    return 0
  fi

  install_binary_from_tar "derailed/k9s" 'k9s_Linux_amd64\.tar\.gz$' "k9s"
}

ensure_kubectx() {
  if command -v kubectx >/dev/null 2>&1; then
    log "kubectx already available"
    return 0
  fi

  install_binary_from_tar "ahmetb/kubectx" 'kubectx_.*_linux_x86_64\.tar\.gz$' "kubectx"
}

ensure_kubens() {
  if command -v kubens >/dev/null 2>&1; then
    log "kubens already available"
    return 0
  fi

  install_binary_from_tar "ahmetb/kubectx" 'kubens_.*_linux_x86_64\.tar\.gz$' "kubens"
}

ensure_helm_diff() {
  require_cmd helm

  if helm plugin list 2>/dev/null | awk 'NR>1 {print $1}' | grep -qx 'diff'; then
    log "helm diff plugin already available"
    return 0
  fi

  helm plugin install https://github.com/databus23/helm-diff >/dev/null
  log "Installed helm diff plugin"
}

ensure_kcat() {
  if command -v kcat >/dev/null 2>&1; then
    log "kcat already available"
    return 0
  fi

  cat >"$INSTALL_BIN_DIR/kcat" <<WRAPPER
#!/usr/bin/env bash
set -euo pipefail

for candidate in /usr/bin/kcat /usr/local/bin/kcat; do
  if [[ -x "\$candidate" ]]; then
    exec "\$candidate" "\$@"
  fi
done

tty_args=()
if [[ -t 0 && -t 1 ]]; then
  tty_args=(-t)
fi

exec docker run --rm -i "\${tty_args[@]}" \
  --network host \
  -v "\$PWD:\$PWD" \
  -w "\$PWD" \
  ${KCAT_IMAGE} "\$@"
WRAPPER
  chmod 0755 "$INSTALL_BIN_DIR/kcat"
  link_local_bin "kcat"
  log "Installed Docker-backed kcat wrapper"
}

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --required-only)
        INSTALL_OPTIONAL=0
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        fail "Unknown argument: $1"
        ;;
    esac
  done

  require_cmd curl
  require_cmd jq
  require_cmd tar
  require_cmd install
  require_cmd chmod
  require_cmd mkdir

  mkdir -p "$INSTALL_BIN_DIR" "$LOCAL_BIN_DIR"
  export PATH="$INSTALL_BIN_DIR:$LOCAL_BIN_DIR:$PATH"

  ensure_trpg
  ensure_yq_v4
  ensure_stern
  ensure_helm_diff

  if [[ "$INSTALL_OPTIONAL" -eq 1 ]]; then
    ensure_k9s
    ensure_kubectx
    ensure_kubens
    ensure_kcat
  fi

  log "Baseline install completed"
}

main "$@"
