#!/usr/bin/env bash
set -euo pipefail

REPO_OWNER="${REPO_OWNER:-meintechblog}"
REPO_NAME="${REPO_NAME:-utm-timevault}"
REPO_REF="${REPO_REF:-main}"
BIN_NAME="utm-timevault"

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
LOCAL_SOURCE="${SCRIPT_DIR}/utm-timevault.sh"
REMOTE_SOURCE="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${REPO_REF}/scripts/utm-timevault.sh"

TMP_FILE=""
cleanup() {
  if [ -n "$TMP_FILE" ] && [ -f "$TMP_FILE" ]; then
    rm -f "$TMP_FILE"
  fi
}
trap cleanup EXIT

log() {
  printf "[install] %s\n" "$*"
}

warn() {
  printf "[install][warn] %s\n" "$*" >&2
}

err() {
  printf "[install][error] %s\n" "$*" >&2
}

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

choose_target_dir() {
  if [ -d "/usr/local/bin" ] && [ -w "/usr/local/bin" ]; then
    printf "/usr/local/bin"
  else
    mkdir -p "$HOME/.local/bin"
    printf "%s" "$HOME/.local/bin"
  fi
}

fetch_source() {
  if [ -f "$LOCAL_SOURCE" ]; then
    log "Using local source: $LOCAL_SOURCE"
    printf "%s" "$LOCAL_SOURCE"
    return 0
  fi

  has_cmd curl || {
    err "curl is required for remote install mode."
    return 1
  }

  TMP_FILE="$(mktemp "${TMPDIR:-/tmp}/utm-timevault.XXXXXX")"
  log "Downloading: $REMOTE_SOURCE"
  curl -fsSL "$REMOTE_SOURCE" -o "$TMP_FILE"
  printf "%s" "$TMP_FILE"
}

install_binary() {
  local src="$1"
  local target_dir="$2"
  local target_file="${target_dir}/${BIN_NAME}"

  if has_cmd install; then
    install -m 0755 "$src" "$target_file"
  else
    cp "$src" "$target_file"
    chmod 0755 "$target_file"
  fi

  log "Installed ${BIN_NAME} to: $target_file"
}

print_dependency_summary() {
  local missing_required=()

  has_cmd bash || missing_required+=("bash")
  has_cmd tar || missing_required+=("tar")
  has_cmd awk || missing_required+=("awk")
  has_cmd du || missing_required+=("du")
  has_cmd date || missing_required+=("date")

  if ! has_cmd rsync && ! has_cmd gzip && ! has_cmd zstd; then
    missing_required+=("rsync|gzip|zstd")
  fi

  if [ "${#missing_required[@]}" -eq 0 ]; then
    log "All required runtime tools look available."
  else
    warn "Missing required runtime tools:"
    for tool in "${missing_required[@]}"; do
      warn "  - ${tool}"
    done
  fi
}

print_next_steps() {
  local target_dir="$1"

  if ! printf '%s' ":$PATH:" | grep -q ":${target_dir}:"; then
    warn "${target_dir} is not in PATH for this shell session."
    warn "Add it, for example: export PATH=\"${target_dir}:\$PATH\""
  fi

  log "Next steps:"
  log "  1) ${BIN_NAME} doctor"
  log "  2) ${BIN_NAME} backup --vm <YourVMName> --keep 14"
  log "  3) ${BIN_NAME} help"
}

main() {
  local src target_dir

  src="$(fetch_source)"
  target_dir="$(choose_target_dir)"
  install_binary "$src" "$target_dir"
  print_dependency_summary
  print_next_steps "$target_dir"
}

main "$@"
