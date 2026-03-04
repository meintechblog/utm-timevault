#!/usr/bin/env bash
set -euo pipefail

VERSION="0.1.3"

EXIT_OK=0
EXIT_RUNTIME=1
EXIT_USAGE=2
EXIT_DEPS=3
EXIT_TIMEOUT=4

OS_UNAME="$(uname -s 2>/dev/null || echo unknown)"
case "$OS_UNAME" in
  Darwin) PLATFORM="macos" ;;
  Linux) PLATFORM="linux" ;;
  *) PLATFORM="unknown" ;;
esac

DEFAULT_UTM_DOCS_DIR_MAC="$HOME/Library/Containers/com.utmapp.UTM/Data/Documents"
DEFAULT_BACKUP_DIR_MAC="/Volumes/BigBadaBoom/Backup/utm"
DEFAULT_UTM_DOCS_DIR_LINUX="${XDG_DATA_HOME:-$HOME/.local/share}/UTM/Documents"
DEFAULT_BACKUP_DIR_LINUX="$HOME/backups/utm"

case "$PLATFORM" in
  macos)
    UTM_DOCS_DIR="${UTM_DOCS_DIR:-$DEFAULT_UTM_DOCS_DIR_MAC}"
    BACKUP_DIR="${BACKUP_DIR:-$DEFAULT_BACKUP_DIR_MAC}"
    ;;
  linux)
    UTM_DOCS_DIR="${UTM_DOCS_DIR:-$DEFAULT_UTM_DOCS_DIR_LINUX}"
    BACKUP_DIR="${BACKUP_DIR:-$DEFAULT_BACKUP_DIR_LINUX}"
    ;;
  *)
    UTM_DOCS_DIR="${UTM_DOCS_DIR:-$DEFAULT_UTM_DOCS_DIR_MAC}"
    BACKUP_DIR="${BACKUP_DIR:-$DEFAULT_BACKUP_DIR_MAC}"
    ;;
esac

KEEP_DEFAULT="${KEEP_DEFAULT:-14}"
RSYNC_SNAPSHOT_CHECKSUM="${RSYNC_SNAPSHOT_CHECKSUM:-1}"
BACKUP_MODE="${BACKUP_MODE:-auto}" # auto|snapshot|archive
UTM_STOP_TIMEOUT_SEC="${UTM_STOP_TIMEOUT_SEC:-120}"
UTM_STOP_POLL_INTERVAL_SEC="${UTM_STOP_POLL_INTERVAL_SEC:-2}"
HARDLINK_AUTO_FALLBACK="${HARDLINK_AUTO_FALLBACK:-1}"

BACKUP_TARGET_HARDLINK_SUPPORT_CACHE=""
BACKUP_TARGET_HARDLINK_CHECK_DETAIL=""

VM_STATE_RESTORE_PENDING=0
VM_STATE_RESTORE_VM=""

info() { printf "[INFO] %s\n" "$*"; }
ok()   { printf "[OK] %s\n" "$*"; }
warn() { printf "[WARN] %s\n" "$*"; }
err()  { printf "[ERROR] %s\n" "$*" >&2; }

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

is_uint() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
    *) return 0 ;;
  esac
}

need_dir() {
  [ -d "$1" ] || {
    err "Directory not found: $1"
    return "$EXIT_RUNTIME"
  }
}

backup_target_supports_hardlinks() {
  local probe_dir probe_src probe_link

  case "${BACKUP_TARGET_HARDLINK_SUPPORT_CACHE:-}" in
    supported) return 0 ;;
    unsupported|uncheckable) return 1 ;;
  esac

  if [ ! -d "$BACKUP_DIR" ]; then
    BACKUP_TARGET_HARDLINK_SUPPORT_CACHE="uncheckable"
    BACKUP_TARGET_HARDLINK_CHECK_DETAIL="backup directory does not exist: $BACKUP_DIR"
    return 1
  fi

  probe_dir="${BACKUP_DIR}/.utm-timevault-hardlink-check-$$-${RANDOM:-0}"
  probe_src="${probe_dir}/src"
  probe_link="${probe_dir}/link"

  if ! mkdir -p "$probe_dir" 2>/dev/null; then
    BACKUP_TARGET_HARDLINK_SUPPORT_CACHE="uncheckable"
    BACKUP_TARGET_HARDLINK_CHECK_DETAIL="cannot create probe directory in backup target"
    return 1
  fi

  if ! printf "probe\n" > "$probe_src" 2>/dev/null; then
    rm -f "$probe_src" "$probe_link" >/dev/null 2>&1 || true
    rmdir "$probe_dir" >/dev/null 2>&1 || true
    BACKUP_TARGET_HARDLINK_SUPPORT_CACHE="uncheckable"
    BACKUP_TARGET_HARDLINK_CHECK_DETAIL="cannot create probe file in backup target"
    return 1
  fi

  if ln "$probe_src" "$probe_link" >/dev/null 2>&1; then
    BACKUP_TARGET_HARDLINK_SUPPORT_CACHE="supported"
    BACKUP_TARGET_HARDLINK_CHECK_DETAIL=""
    rm -f "$probe_src" "$probe_link" >/dev/null 2>&1 || true
    rmdir "$probe_dir" >/dev/null 2>&1 || true
    return 0
  fi

  BACKUP_TARGET_HARDLINK_SUPPORT_CACHE="unsupported"
  BACKUP_TARGET_HARDLINK_CHECK_DETAIL="hard links are not supported or blocked on backup target"
  rm -f "$probe_src" "$probe_link" >/dev/null 2>&1 || true
  rmdir "$probe_dir" >/dev/null 2>&1 || true
  return 1
}

apply_hardlink_capability_policy() {
  local outvar="$1"
  local requested_kind="$2"
  local resolved_kind="$requested_kind"

  if [ "$requested_kind" != "snapshot" ]; then
    printf -v "$outvar" "%s" "$resolved_kind"
    return 0
  fi

  if backup_target_supports_hardlinks; then
    printf -v "$outvar" "%s" "$resolved_kind"
    return 0
  fi

  case "${BACKUP_TARGET_HARDLINK_SUPPORT_CACHE:-unsupported}" in
    unsupported)
      warn "Backup target '$BACKUP_DIR' does not support hard links. Snapshot deduplication cannot work there."
      ;;
    uncheckable)
      warn "Could not verify hard-link support for '$BACKUP_DIR': ${BACKUP_TARGET_HARDLINK_CHECK_DETAIL:-unknown reason}."
      ;;
    *)
      warn "Hard-link capability check returned an unknown state for '$BACKUP_DIR'."
      ;;
  esac

  case "${HARDLINK_AUTO_FALLBACK:-1}" in
    ''|1)
      warn "HARDLINK_AUTO_FALLBACK=1 -> switching backup mode from snapshot to archive."
      resolved_kind="archive"
      ;;
    0)
      warn "HARDLINK_AUTO_FALLBACK=0 -> keeping snapshot mode (full-copy behavior expected)."
      resolved_kind="snapshot"
      ;;
    *)
      warn "Invalid HARDLINK_AUTO_FALLBACK='$HARDLINK_AUTO_FALLBACK'. Treating it as 1 (auto fallback enabled)."
      warn "Switching backup mode from snapshot to archive."
      resolved_kind="archive"
      ;;
  esac

  printf -v "$outvar" "%s" "$resolved_kind"
  return 0
}

usage() {
  cat <<USAGE
UTM TimeVault v$VERSION

Usage:
  utm-timevault                    # open interactive menu (backward compatible)
  utm-timevault menu
  utm-timevault backup --vm <name> [--keep <n>] [--mode auto|snapshot|archive] [--checksum 0|1] [--backup-dir <path>] [--utm-docs-dir <path>] [--timeout <sec>] [--poll <sec>]
  utm-timevault restore --vm <name> --source <path> [--yes] [--backup-dir <path>] [--utm-docs-dir <path>] [--timeout <sec>] [--poll <sec>]
  utm-timevault list-vms [--utm-docs-dir <path>]
  utm-timevault list-backups --vm <name> [--backup-dir <path>]
  utm-timevault doctor
  utm-timevault version
  utm-timevault help
USAGE
}

usage_backup() {
  cat <<USAGE
Usage:
  utm-timevault backup --vm <name> [--keep <n>] [--mode auto|snapshot|archive] [--checksum 0|1] [--backup-dir <path>] [--utm-docs-dir <path>] [--timeout <sec>] [--poll <sec>]
USAGE
}

usage_restore() {
  cat <<USAGE
Usage:
  utm-timevault restore --vm <name> --source <path> [--yes] [--backup-dir <path>] [--utm-docs-dir <path>] [--timeout <sec>] [--poll <sec>]
USAGE
}

usage_list_vms() {
  cat <<USAGE
Usage:
  utm-timevault list-vms [--utm-docs-dir <path>]
USAGE
}

usage_list_backups() {
  cat <<USAGE
Usage:
  utm-timevault list-backups --vm <name> [--backup-dir <path>]
USAGE
}

dir_size_bytes() {
  du -sk "$1" 2>/dev/null | awk '{print $1*1024}'
}

file_size_bytes() {
  stat -f%z "$1" 2>/dev/null || stat -c%s "$1" 2>/dev/null || wc -c < "$1" 2>/dev/null || true
}

file_mtime_epoch() {
  stat -f%m "$1" 2>/dev/null || stat -c%Y "$1" 2>/dev/null || echo 0
}

human_size_path() {
  if [ -d "$1" ]; then
    du -sh "$1" 2>/dev/null | awk '{print $1}'
  else
    du -sh "$1" 2>/dev/null | awk '{print $1}'
  fi
}

rsync_progress_option() {
  if rsync --help 2>/dev/null | grep -q -- '--info'; then
    echo "--info=progress2"
  else
    echo "--progress"
  fi
}

compression_mode() {
  if has_cmd zstd; then
    echo "zstd"
  else
    echo "gzip"
  fi
}

progress_pipe() {
  local size="${1:-}"
  if has_cmd pv; then
    if [ -n "$size" ] && [ "$size" -gt 0 ] 2>/dev/null; then
      pv -pterab -s "$size"
    else
      pv -pterab
    fi
  else
    cat
  fi
}

progress_file() {
  local file="$1"
  local size="${2:-}"
  if has_cmd pv; then
    if [ -n "$size" ] && [ "$size" -gt 0 ] 2>/dev/null; then
      pv -pterab -s "$size" "$file"
    else
      pv -pterab "$file"
    fi
  else
    cat "$file"
  fi
}

collect_vm_backups_sorted() {
  local vm="$1"
  local p mt
  local paths=()

  for p in "$BACKUP_DIR"/"${vm}.utm_"*.snapshot \
           "$BACKUP_DIR"/"${vm}.utm_"*.tar.gz \
           "$BACKUP_DIR"/"${vm}.utm_"*.tar.zst; do
    [ -e "$p" ] || continue
    paths+=( "$p" )
  done

  [ "${#paths[@]}" -eq 0 ] && return 0

  for p in "${paths[@]}"; do
    mt="$(file_mtime_epoch "$p")"
    printf "%s\t%s\n" "$mt" "$p"
  done | sort -rn | cut -f2-
}

collect_vm_backups_sorted_by_kind() {
  local vm="$1"
  local kind="$2" # snapshot|archive
  local p mt
  local paths=()

  case "$kind" in
    snapshot)
      for p in "$BACKUP_DIR"/"${vm}.utm_"*.snapshot; do
        [ -e "$p" ] || continue
        paths+=( "$p" )
      done
      ;;
    archive)
      for p in "$BACKUP_DIR"/"${vm}.utm_"*.tar.gz \
               "$BACKUP_DIR"/"${vm}.utm_"*.tar.zst; do
        [ -e "$p" ] || continue
        paths+=( "$p" )
      done
      ;;
    *)
      return 0
      ;;
  esac

  [ "${#paths[@]}" -eq 0 ] && return 0

  for p in "${paths[@]}"; do
    mt="$(file_mtime_epoch "$p")"
    printf "%s\t%s\n" "$mt" "$p"
  done | sort -rn | cut -f2-
}

latest_snapshot_for_vm() {
  local vm="$1"
  collect_vm_backups_sorted_by_kind "$vm" snapshot | awk 'NF{print; exit}'
}

rotate_vm_backups_global() {
  local vm="$1"
  local keep="$2"
  local files

  files="$(collect_vm_backups_sorted "$vm" || true)"
  if [ -n "$files" ]; then
    printf "%s\n" "$files" | awk -v k="$keep" 'NR>k{print}' | while IFS= read -r f; do
      [ -n "$f" ] || continue
      warn "Deleting old backup: $(basename "$f")"
      if [ -d "$f" ]; then
        rm -rf "$f"
      else
        rm -f "$f"
      fi
    done
  fi
}

list_vm_names() {
  local p
  for p in "$UTM_DOCS_DIR"/*.utm; do
    [ -e "$p" ] || continue
    basename "$p" .utm
  done
}

utm_stop_best_effort() {
  local vm="$1"
  local method="${2:-force}"
  if [ "$PLATFORM" = "macos" ] && has_cmd osascript; then
    case "$method" in
      request)
        osascript - "$vm" >/dev/null 2>&1 <<'APPLESCRIPT' || true
on run argv
  set vmName to item 1 of argv
  tell application "UTM"
    stop (first virtual machine whose name is vmName) by request
  end tell
end run
APPLESCRIPT
        ;;
      force)
        osascript - "$vm" >/dev/null 2>&1 <<'APPLESCRIPT' || true
on run argv
  set vmName to item 1 of argv
  tell application "UTM"
    stop (first virtual machine whose name is vmName) by force
  end tell
end run
APPLESCRIPT
        ;;
      kill)
        osascript - "$vm" >/dev/null 2>&1 <<'APPLESCRIPT' || true
on run argv
  set vmName to item 1 of argv
  tell application "UTM"
    stop (first virtual machine whose name is vmName) by kill
  end tell
end run
APPLESCRIPT
        ;;
      *)
        osascript - "$vm" >/dev/null 2>&1 <<'APPLESCRIPT' || true
on run argv
  set vmName to item 1 of argv
  tell application "UTM"
    stop (first virtual machine whose name is vmName)
  end tell
end run
APPLESCRIPT
        ;;
    esac
  fi
}

utm_start_best_effort() {
  local vm="$1"
  if [ "$PLATFORM" = "macos" ] && has_cmd osascript; then
    osascript - "$vm" >/dev/null 2>&1 <<'APPLESCRIPT' || true
on run argv
  set vmName to item 1 of argv
  tell application "UTM"
    start (first virtual machine whose name is vmName)
  end tell
end run
APPLESCRIPT
  fi
}

utm_vm_status() {
  local vm="$1"
  if [ "$PLATFORM" = "macos" ] && has_cmd osascript; then
    osascript - "$vm" 2>/dev/null <<'APPLESCRIPT' || true
on run argv
  set vmName to item 1 of argv
  tell application "UTM"
    return status of (first virtual machine whose name is vmName) as string
  end tell
end run
APPLESCRIPT
  fi
}

wait_for_vm_status() {
  local vm="$1"
  local desired="$2"
  local timeout="${3:-$UTM_STOP_TIMEOUT_SEC}"
  local poll_interval="${4:-$UTM_STOP_POLL_INTERVAL_SEC}"
  local start now elapsed status

  if ! is_uint "$timeout" || [ "$timeout" -lt 1 ]; then
    timeout=120
  fi
  if ! is_uint "$poll_interval" || [ "$poll_interval" -lt 1 ]; then
    poll_interval=2
  fi

  if [ "$PLATFORM" != "macos" ] || ! has_cmd osascript; then
    warn "VM status check unavailable on PLATFORM=$PLATFORM. Continuing without status polling."
    return "$EXIT_OK"
  fi

  start="$(date +%s)"
  while true; do
    status="$(utm_vm_status "$vm" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
    if [ "$status" = "$desired" ]; then
      ok "VM '$vm' reached status '$desired'."
      return "$EXIT_OK"
    fi

    now="$(date +%s)"
    elapsed=$((now - start))
    if [ "$elapsed" -ge "$timeout" ]; then
      err "Timeout: VM '$vm' did not reach '$desired' within ${timeout}s (last status: ${status:-unknown})."
      return "$EXIT_TIMEOUT"
    fi

    sleep "$poll_interval"
  done
}

stop_vm_with_graceful_fallback() {
  local vm="$1"
  local timeout="${2:-$UTM_STOP_TIMEOUT_SEC}"
  local poll_interval="${3:-$UTM_STOP_POLL_INTERVAL_SEC}"

  info "Requesting graceful guest shutdown: $vm"
  utm_stop_best_effort "$vm" "request"
  if wait_for_vm_status "$vm" "stopped" "$timeout" "$poll_interval"; then
    return "$EXIT_OK"
  fi

  warn "Graceful shutdown timed out. Escalating to force stop: $vm"
  utm_stop_best_effort "$vm" "force"
  wait_for_vm_status "$vm" "stopped" "$timeout" "$poll_interval"
}

restore_vm_state_if_needed() {
  local vm
  if [ "${VM_STATE_RESTORE_PENDING:-0}" != "1" ]; then
    return "$EXIT_OK"
  fi

  vm="${VM_STATE_RESTORE_VM:-}"
  [ -n "$vm" ] || {
    VM_STATE_RESTORE_PENDING=0
    VM_STATE_RESTORE_VM=""
    return "$EXIT_OK"
  }

  info "Restoring pre-backup VM state: starting '$vm'..."
  utm_start_best_effort "$vm"
  if ! wait_for_vm_status "$vm" "started" "$UTM_STOP_TIMEOUT_SEC" "$UTM_STOP_POLL_INTERVAL_SEC"; then
    warn "Automatic VM start failed for '$vm'."
    return "$?"
  fi

  VM_STATE_RESTORE_PENDING=0
  VM_STATE_RESTORE_VM=""
  return "$EXIT_OK"
}

on_exit() {
  local rc=$?
  local restore_rc=0
  trap - EXIT

  if [ "${VM_STATE_RESTORE_PENDING:-0}" = "1" ]; then
    restore_vm_state_if_needed || restore_rc=$?
  fi

  if [ "$rc" -eq 0 ] && [ "$restore_rc" -ne 0 ]; then
    rc="$restore_rc"
  fi

  exit "$rc"
}

trap on_exit EXIT

collect_missing_required_tools() {
  local missing=()

  has_cmd tar || missing+=("tar")
  has_cmd awk || missing+=("awk")
  has_cmd du || missing+=("du")
  has_cmd date || missing+=("date")
  if ! has_cmd rsync && ! has_cmd gzip && ! has_cmd zstd; then
    missing+=("rsync|gzip|zstd")
  fi

  if [ "${#missing[@]}" -eq 0 ]; then
    return 0
  fi

  printf "%s\n" "${missing[@]}"
}

collect_missing_optional_tools() {
  local missing=()

  has_cmd pv || missing+=("pv")
  has_cmd rsync || missing+=("rsync")
  has_cmd zstd || missing+=("zstd")

  if [ "${#missing[@]}" -eq 0 ]; then
    return 0
  fi

  printf "%s\n" "${missing[@]}"
}

require_dependencies() {
  local missing_required
  missing_required="$(collect_missing_required_tools || true)"
  if [ -n "$missing_required" ]; then
    err "Missing required tools:"
    printf "%s\n" "$missing_required" | while IFS= read -r tool; do
      err "  - $tool"
    done
    return "$EXIT_DEPS"
  fi
  return "$EXIT_OK"
}

doctor() {
  local missing_required missing_optional

  echo "UTM TimeVault doctor"
  echo "Platform: $PLATFORM ($OS_UNAME)"
  echo "UTM docs: $UTM_DOCS_DIR"
  echo "Backups:  $BACKUP_DIR"
  if [ "$PLATFORM" != "macos" ]; then
    warn "Official support scope is macOS. Linux is experimental."
  fi

  missing_required="$(collect_missing_required_tools || true)"
  missing_optional="$(collect_missing_optional_tools || true)"

  if backup_target_supports_hardlinks; then
    ok "Backup target hard-link support: available."
  else
    case "${BACKUP_TARGET_HARDLINK_SUPPORT_CACHE:-unsupported}" in
      unsupported)
        warn "Backup target hard-link support: unavailable."
        warn "Snapshot deduplication via --link-dest will not work on this target."
        ;;
      uncheckable)
        warn "Backup target hard-link support: could not be verified."
        warn "Reason: ${BACKUP_TARGET_HARDLINK_CHECK_DETAIL:-unknown reason}."
        ;;
      *)
        warn "Backup target hard-link support: unknown status."
        ;;
    esac
  fi

  if [ -z "$missing_required" ]; then
    ok "All required tools are present."
  else
    err "Missing required tools:"
    printf "%s\n" "$missing_required" | while IFS= read -r tool; do
      err "  - $tool"
    done
  fi

  if [ -z "$missing_optional" ]; then
    ok "All optional tools are present."
  else
    warn "Missing optional tools:"
    printf "%s\n" "$missing_optional" | while IFS= read -r tool; do
      warn "  - $tool"
    done
  fi

  if [ -n "$missing_required" ]; then
    return "$EXIT_DEPS"
  fi
  return "$EXIT_OK"
}

pick_vm_interactive() {
  local vms=()
  local p sel count i

  need_dir "$UTM_DOCS_DIR" || return "$EXIT_RUNTIME"

  for p in "$UTM_DOCS_DIR"/*.utm; do
    [ -e "$p" ] || continue
    vms+=("$(basename "$p")")
  done

  count="${#vms[@]}"
  if [ "$count" -eq 0 ]; then
    err "No .utm VM found in: $UTM_DOCS_DIR"
    return "$EXIT_RUNTIME"
  fi

  echo "Select VM:"
  i=1
  while [ "$i" -le "$count" ]; do
    echo "  [$i] ${vms[$((i-1))]}"
    i=$((i+1))
  done
  echo "  [0] Cancel"

  read -r -p "> " sel
  if ! is_uint "$sel"; then
    err "Invalid selection."
    return "$EXIT_USAGE"
  fi

  if [ "$sel" -eq 0 ]; then
    return "$EXIT_RUNTIME"
  fi

  if [ "$sel" -gt "$count" ]; then
    err "Invalid selection."
    return "$EXIT_USAGE"
  fi

  echo "${vms[$((sel-1))]%.utm}"
}

pick_backup_interactive() {
  local vm="$1"
  local backups count sel kind size i

  backups="$(collect_vm_backups_sorted "$vm" || true)"
  if [ -z "$backups" ]; then
    err "No backups found for '$vm' in: $BACKUP_DIR"
    return "$EXIT_RUNTIME"
  fi

  echo "Available backups (newest first):"
  i=1
  printf "%s\n" "$backups" | while IFS= read -r f; do
    [ -n "$f" ] || continue
    if [ -d "$f" ]; then
      kind="snapshot"
    else
      kind="archive"
    fi
    size="$(human_size_path "$f")"
    printf "  [%d] %s [%s] (%s)\n" "$i" "$(basename "$f")" "$kind" "${size:-?}"
    i=$((i+1))
  done
  echo "  [0] Cancel"

  count="$(printf "%s\n" "$backups" | awk 'NF{c++} END{print c+0}')"
  read -r -p "> " sel
  if ! is_uint "$sel"; then
    err "Invalid selection."
    return "$EXIT_USAGE"
  fi

  if [ "$sel" -eq 0 ]; then
    return "$EXIT_RUNTIME"
  fi

  if [ "$sel" -gt "$count" ]; then
    err "Invalid selection."
    return "$EXIT_USAGE"
  fi

  printf "%s\n" "$backups" | awk -v n="$sel" 'NR==n{print; exit}'
}

do_backup_for_vm() {
  local vm="$1"
  local keep="$2"
  local vm_bundle src_path ts out mode src_size
  local backup_kind snapshot_dir prev_snapshot rsync_opt suffix_idx
  local vm_status_before
  local rsync_args=()

  need_dir "$UTM_DOCS_DIR" || return "$EXIT_RUNTIME"
  mkdir -p "$BACKUP_DIR"

  vm_bundle="${vm}.utm"
  src_path="${UTM_DOCS_DIR}/${vm_bundle}"
  [ -d "$src_path" ] || {
    err "VM not found: $src_path"
    return "$EXIT_RUNTIME"
  }

  src_size="$(dir_size_bytes "$src_path")"

  vm_status_before="$(utm_vm_status "$vm" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
  VM_STATE_RESTORE_PENDING=0
  VM_STATE_RESTORE_VM=""
  if [ "$vm_status_before" = "started" ]; then
    VM_STATE_RESTORE_PENDING=1
    VM_STATE_RESTORE_VM="$vm"
    info "VM was running before backup and will be started again after backup."
  else
    info "VM was not running before backup (status: ${vm_status_before:-unknown})."
  fi

  if ! stop_vm_with_graceful_fallback "$vm" "$UTM_STOP_TIMEOUT_SEC" "$UTM_STOP_POLL_INTERVAL_SEC"; then
    return "$?"
  fi

  ts="$(date +%Y-%m-%d_%H-%M-%S)"

  case "$BACKUP_MODE" in
    snapshot) backup_kind="snapshot" ;;
    archive) backup_kind="archive" ;;
    auto|'')
      if has_cmd rsync; then
        backup_kind="snapshot"
      else
        backup_kind="archive"
      fi
      ;;
    *)
      warn "Unknown BACKUP_MODE='$BACKUP_MODE'. Falling back to auto."
      if has_cmd rsync; then
        backup_kind="snapshot"
      else
        backup_kind="archive"
      fi
      ;;
  esac

  if [ "$backup_kind" = "snapshot" ] && ! has_cmd rsync; then
    warn "Snapshot mode requested, but rsync is missing. Falling back to archive mode."
    backup_kind="archive"
  fi

  apply_hardlink_capability_policy backup_kind "$backup_kind"

  if [ "$backup_kind" = "snapshot" ]; then
    snapshot_dir="${BACKUP_DIR}/${vm}.utm_${ts}.snapshot"
    if [ -e "$snapshot_dir" ]; then
      suffix_idx=1
      while [ -e "${BACKUP_DIR}/${vm}.utm_${ts}_${suffix_idx}.snapshot" ]; do
        suffix_idx=$((suffix_idx+1))
      done
      snapshot_dir="${BACKUP_DIR}/${vm}.utm_${ts}_${suffix_idx}.snapshot"
    fi

    prev_snapshot="$(latest_snapshot_for_vm "$vm" || true)"

    info "Backup mode: snapshot (rsync + hard links)."
    if [ "$RSYNC_SNAPSHOT_CHECKSUM" = "1" ]; then
      info "Change detection: strict checksum mode (--checksum)."
    else
      warn "Change detection: size+mtime mode (faster, less strict)."
    fi

    if [ -n "$prev_snapshot" ] && [ -d "$prev_snapshot/$vm_bundle" ]; then
      info "Base snapshot: $(basename "$prev_snapshot")"
    else
      info "No base snapshot found. First run is a full copy."
    fi

    mkdir -p "$snapshot_dir/$vm_bundle"
    info "Creating snapshot: $(basename "$snapshot_dir")"

    rsync_opt=""
    if [ -t 1 ]; then
      rsync_opt="$(rsync_progress_option)"
    fi

    rsync_args=(rsync -a --delete)
    if [ "$RSYNC_SNAPSHOT_CHECKSUM" = "1" ]; then
      rsync_args+=(--checksum)
    fi
    if [ -n "$rsync_opt" ]; then
      rsync_args+=("$rsync_opt")
    fi
    if [ -n "$prev_snapshot" ] && [ -d "$prev_snapshot/$vm_bundle" ]; then
      rsync_args+=(--link-dest="$prev_snapshot/$vm_bundle")
    fi

    rsync_args+=("$src_path/" "$snapshot_dir/$vm_bundle/")
    "${rsync_args[@]}"

    ok "Snapshot created: $snapshot_dir"
    info "Used storage: $(human_size_path "$snapshot_dir")"

    info "Rotation: keeping $keep backups for '$vm'..."
    rotate_vm_backups_global "$vm" "$keep"
  else
    mode="$(compression_mode)"
    info "Backup mode: archive (full tar)."

    if [ "$mode" = "zstd" ]; then
      out="${BACKUP_DIR}/${vm}.utm_${ts}.tar.zst"
      if [ -e "$out" ]; then
        suffix_idx=1
        while [ -e "${BACKUP_DIR}/${vm}.utm_${ts}_${suffix_idx}.tar.zst" ]; do
          suffix_idx=$((suffix_idx+1))
        done
        out="${BACKUP_DIR}/${vm}.utm_${ts}_${suffix_idx}.tar.zst"
      fi
      info "Creating backup (zstd): $(basename "$out")"
      if has_cmd pv; then
        tar -C "$UTM_DOCS_DIR" -cf - "$vm_bundle" | progress_pipe "$src_size" | zstd -T0 -q -o "$out"
      else
        tar -C "$UTM_DOCS_DIR" -cf - "$vm_bundle" | zstd -T0 --progress -o "$out"
      fi
    else
      out="${BACKUP_DIR}/${vm}.utm_${ts}.tar.gz"
      if [ -e "$out" ]; then
        suffix_idx=1
        while [ -e "${BACKUP_DIR}/${vm}.utm_${ts}_${suffix_idx}.tar.gz" ]; do
          suffix_idx=$((suffix_idx+1))
        done
        out="${BACKUP_DIR}/${vm}.utm_${ts}_${suffix_idx}.tar.gz"
      fi
      info "Creating backup (gzip): $(basename "$out")"
      tar -C "$UTM_DOCS_DIR" -cf - "$vm_bundle" | progress_pipe "$src_size" | gzip > "$out"
    fi

    ok "Backup created: $out"
    info "Rotation: keeping $keep backups for '$vm'..."
    rotate_vm_backups_global "$vm" "$keep"
  fi

  if [ "$VM_STATE_RESTORE_PENDING" = "1" ]; then
    restore_vm_state_if_needed || return "$?"
  fi

  ok "Backup flow completed."
  return "$EXIT_OK"
}

do_restore_for_vm_and_source() {
  local vm="$1"
  local source="$2"
  local assume_yes="$3"
  local dest_vm old_ts archive_size snapshot_src rsync_opt

  need_dir "$UTM_DOCS_DIR" || return "$EXIT_RUNTIME"
  need_dir "$BACKUP_DIR" || return "$EXIT_RUNTIME"

  [ -e "$source" ] || {
    err "Backup source not found: $source"
    return "$EXIT_RUNTIME"
  }

  if [ "$assume_yes" != "1" ]; then
    if [ ! -t 0 ]; then
      err "Non-interactive restore requires --yes."
      return "$EXIT_USAGE"
    fi
    echo "This will overwrite VM '$vm'. Existing VM folder will be renamed to .old_<timestamp>."
    echo "Selected backup: $(basename "$source")"
    read -r -p "Proceed? (y/N): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
      info "Restore cancelled."
      return "$EXIT_OK"
    fi
  fi

  if ! stop_vm_with_graceful_fallback "$vm" "$UTM_STOP_TIMEOUT_SEC" "$UTM_STOP_POLL_INTERVAL_SEC"; then
    return "$?"
  fi

  dest_vm="${UTM_DOCS_DIR}/${vm}.utm"
  if [ -d "$dest_vm" ]; then
    old_ts="$(date +%Y-%m-%d_%H-%M-%S)"
    info "Renaming existing VM to: ${vm}.utm.old_${old_ts}"
    mv "$dest_vm" "${dest_vm}.old_${old_ts}"
  fi

  archive_size=""
  [ -f "$source" ] && archive_size="$(file_size_bytes "$source")"

  info "Restoring backup..."
  case "$source" in
    *.snapshot)
      snapshot_src="${source}/${vm}.utm"
      [ -d "$snapshot_src" ] || {
        err "Invalid snapshot content. Missing: $snapshot_src"
        return "$EXIT_RUNTIME"
      }
      if has_cmd rsync; then
        mkdir -p "$dest_vm"
        rsync_opt=""
        if [ -t 1 ]; then
          rsync_opt="$(rsync_progress_option)"
        fi
        if [ -n "$rsync_opt" ]; then
          rsync -a --delete "$rsync_opt" "$snapshot_src/" "$dest_vm/"
        else
          rsync -a --delete "$snapshot_src/" "$dest_vm/"
        fi
      else
        cp -a "$snapshot_src" "$dest_vm"
      fi
      ;;
    *.tar.gz)
      if has_cmd pv; then
        progress_file "$source" "$archive_size" | tar -xzf - -C "$UTM_DOCS_DIR"
      else
        tar -xzf "$source" -C "$UTM_DOCS_DIR"
      fi
      ;;
    *.tar.zst)
      has_cmd zstd || {
        err "zstd is required to restore .tar.zst backups."
        return "$EXIT_DEPS"
      }
      if has_cmd pv; then
        progress_file "$source" "$archive_size" | zstd -q -dc | tar -xf - -C "$UTM_DOCS_DIR"
      else
        zstd --progress -dc "$source" | tar -xf - -C "$UTM_DOCS_DIR"
      fi
      ;;
    *)
      err "Unsupported backup format: $source"
      return "$EXIT_USAGE"
      ;;
  esac

  ok "Restore completed: ${UTM_DOCS_DIR}/${vm}.utm"
  return "$EXIT_OK"
}

do_backup_interactive() {
  local vm keep_in keep

  vm="$(pick_vm_interactive)" || return "$?"

  keep="$KEEP_DEFAULT"
  read -r -p "How many backups to keep? [$KEEP_DEFAULT]: " keep_in
  keep_in="${keep_in:-$KEEP_DEFAULT}"
  if ! is_uint "$keep_in" || [ "$keep_in" -lt 1 ]; then
    err "KEEP must be a number >= 1."
    return "$EXIT_USAGE"
  fi
  keep="$keep_in"

  do_backup_for_vm "$vm" "$keep"
}

do_restore_interactive() {
  local vm source

  vm="$(pick_vm_interactive)" || return "$?"
  source="$(pick_backup_interactive "$vm")" || return "$?"

  do_restore_for_vm_and_source "$vm" "$source" "0"
}

main_menu() {
  local choice rc

  mkdir -p "$BACKUP_DIR" 2>/dev/null || true
  if ! require_dependencies; then
    return "$?"
  fi

  echo "UTM TimeVault v$VERSION"
  echo "Platform:  $PLATFORM ($OS_UNAME)"
  echo "UTM VMs:   $UTM_DOCS_DIR"
  echo "Backups:   $BACKUP_DIR"
  echo

  while true; do
    echo "Choose action:"
    echo "  [1] Create backup (+ rotation)"
    echo "  [2] Restore (choose backup)"
    echo "  [3] List VMs"
    echo "  [4] Doctor"
    echo "  [0] Exit"
    read -r -p "> " choice
    case "$choice" in
      1)
        if ! do_backup_interactive; then
          rc=$?
          err "Backup failed with exit code $rc"
        fi
        echo
        ;;
      2)
        if ! do_restore_interactive; then
          rc=$?
          err "Restore failed with exit code $rc"
        fi
        echo
        ;;
      3)
        list_vm_names | awk 'NF{print "- "$0}'
        echo
        ;;
      4)
        if ! doctor; then
          rc=$?
          err "Doctor returned exit code $rc"
        fi
        echo
        ;;
      0)
        ok "Bye."
        return "$EXIT_OK"
        ;;
      *)
        err "Invalid selection."
        echo
        ;;
    esac
  done
}

cmd_backup() {
  local vm=""
  local keep="$KEEP_DEFAULT"
  local mode="$BACKUP_MODE"
  local checksum="$RSYNC_SNAPSHOT_CHECKSUM"

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --vm)
        [ "$#" -gt 1 ] || { err "--vm requires a value."; usage_backup; return "$EXIT_USAGE"; }
        vm="$2"
        shift 2
        ;;
      --keep)
        [ "$#" -gt 1 ] || { err "--keep requires a value."; usage_backup; return "$EXIT_USAGE"; }
        keep="$2"
        shift 2
        ;;
      --mode)
        [ "$#" -gt 1 ] || { err "--mode requires a value."; usage_backup; return "$EXIT_USAGE"; }
        mode="$2"
        shift 2
        ;;
      --checksum)
        [ "$#" -gt 1 ] || { err "--checksum requires a value."; usage_backup; return "$EXIT_USAGE"; }
        checksum="$2"
        shift 2
        ;;
      --backup-dir)
        [ "$#" -gt 1 ] || { err "--backup-dir requires a value."; usage_backup; return "$EXIT_USAGE"; }
        BACKUP_DIR="$2"
        shift 2
        ;;
      --utm-docs-dir)
        [ "$#" -gt 1 ] || { err "--utm-docs-dir requires a value."; usage_backup; return "$EXIT_USAGE"; }
        UTM_DOCS_DIR="$2"
        shift 2
        ;;
      --timeout)
        [ "$#" -gt 1 ] || { err "--timeout requires a value."; usage_backup; return "$EXIT_USAGE"; }
        UTM_STOP_TIMEOUT_SEC="$2"
        shift 2
        ;;
      --poll)
        [ "$#" -gt 1 ] || { err "--poll requires a value."; usage_backup; return "$EXIT_USAGE"; }
        UTM_STOP_POLL_INTERVAL_SEC="$2"
        shift 2
        ;;
      -h|--help)
        usage_backup
        return "$EXIT_OK"
        ;;
      *)
        err "Unknown option: $1"
        usage_backup
        return "$EXIT_USAGE"
        ;;
    esac
  done

  [ -n "$vm" ] || { err "--vm is required."; usage_backup; return "$EXIT_USAGE"; }
  if ! is_uint "$keep" || [ "$keep" -lt 1 ]; then
    err "--keep must be >= 1."
    return "$EXIT_USAGE"
  fi
  if ! is_uint "$UTM_STOP_TIMEOUT_SEC" || [ "$UTM_STOP_TIMEOUT_SEC" -lt 1 ]; then
    err "--timeout must be >= 1."
    return "$EXIT_USAGE"
  fi
  if ! is_uint "$UTM_STOP_POLL_INTERVAL_SEC" || [ "$UTM_STOP_POLL_INTERVAL_SEC" -lt 1 ]; then
    err "--poll must be >= 1."
    return "$EXIT_USAGE"
  fi

  case "$mode" in
    auto|snapshot|archive) ;;
    *) err "--mode must be one of: auto, snapshot, archive."; return "$EXIT_USAGE" ;;
  esac

  case "$checksum" in
    0|1) ;;
    *) err "--checksum must be 0 or 1."; return "$EXIT_USAGE" ;;
  esac

  BACKUP_MODE="$mode"
  RSYNC_SNAPSHOT_CHECKSUM="$checksum"

  require_dependencies || return "$?"
  do_backup_for_vm "$vm" "$keep"
}

cmd_restore() {
  local vm=""
  local source=""
  local assume_yes="0"

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --vm)
        [ "$#" -gt 1 ] || { err "--vm requires a value."; usage_restore; return "$EXIT_USAGE"; }
        vm="$2"
        shift 2
        ;;
      --source)
        [ "$#" -gt 1 ] || { err "--source requires a value."; usage_restore; return "$EXIT_USAGE"; }
        source="$2"
        shift 2
        ;;
      --yes)
        assume_yes="1"
        shift
        ;;
      --backup-dir)
        [ "$#" -gt 1 ] || { err "--backup-dir requires a value."; usage_restore; return "$EXIT_USAGE"; }
        BACKUP_DIR="$2"
        shift 2
        ;;
      --utm-docs-dir)
        [ "$#" -gt 1 ] || { err "--utm-docs-dir requires a value."; usage_restore; return "$EXIT_USAGE"; }
        UTM_DOCS_DIR="$2"
        shift 2
        ;;
      --timeout)
        [ "$#" -gt 1 ] || { err "--timeout requires a value."; usage_restore; return "$EXIT_USAGE"; }
        UTM_STOP_TIMEOUT_SEC="$2"
        shift 2
        ;;
      --poll)
        [ "$#" -gt 1 ] || { err "--poll requires a value."; usage_restore; return "$EXIT_USAGE"; }
        UTM_STOP_POLL_INTERVAL_SEC="$2"
        shift 2
        ;;
      -h|--help)
        usage_restore
        return "$EXIT_OK"
        ;;
      *)
        err "Unknown option: $1"
        usage_restore
        return "$EXIT_USAGE"
        ;;
    esac
  done

  [ -n "$vm" ] || { err "--vm is required."; usage_restore; return "$EXIT_USAGE"; }
  [ -n "$source" ] || { err "--source is required."; usage_restore; return "$EXIT_USAGE"; }
  if ! is_uint "$UTM_STOP_TIMEOUT_SEC" || [ "$UTM_STOP_TIMEOUT_SEC" -lt 1 ]; then
    err "--timeout must be >= 1."
    return "$EXIT_USAGE"
  fi
  if ! is_uint "$UTM_STOP_POLL_INTERVAL_SEC" || [ "$UTM_STOP_POLL_INTERVAL_SEC" -lt 1 ]; then
    err "--poll must be >= 1."
    return "$EXIT_USAGE"
  fi

  require_dependencies || return "$?"
  do_restore_for_vm_and_source "$vm" "$source" "$assume_yes"
}

cmd_list_vms() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --utm-docs-dir)
        [ "$#" -gt 1 ] || { err "--utm-docs-dir requires a value."; usage_list_vms; return "$EXIT_USAGE"; }
        UTM_DOCS_DIR="$2"
        shift 2
        ;;
      -h|--help)
        usage_list_vms
        return "$EXIT_OK"
        ;;
      *)
        err "Unknown option: $1"
        usage_list_vms
        return "$EXIT_USAGE"
        ;;
    esac
  done

  need_dir "$UTM_DOCS_DIR" || return "$EXIT_RUNTIME"
  list_vm_names
}

cmd_list_backups() {
  local vm=""

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --vm)
        [ "$#" -gt 1 ] || { err "--vm requires a value."; usage_list_backups; return "$EXIT_USAGE"; }
        vm="$2"
        shift 2
        ;;
      --backup-dir)
        [ "$#" -gt 1 ] || { err "--backup-dir requires a value."; usage_list_backups; return "$EXIT_USAGE"; }
        BACKUP_DIR="$2"
        shift 2
        ;;
      -h|--help)
        usage_list_backups
        return "$EXIT_OK"
        ;;
      *)
        err "Unknown option: $1"
        usage_list_backups
        return "$EXIT_USAGE"
        ;;
    esac
  done

  [ -n "$vm" ] || { err "--vm is required."; usage_list_backups; return "$EXIT_USAGE"; }
  need_dir "$BACKUP_DIR" || return "$EXIT_RUNTIME"

  collect_vm_backups_sorted "$vm"
}

main() {
  local cmd

  if [ "$#" -eq 0 ]; then
    cmd="menu"
  else
    cmd="$1"
    shift
  fi

  case "$cmd" in
    menu)
      main_menu "$@"
      ;;
    backup)
      cmd_backup "$@"
      ;;
    restore)
      cmd_restore "$@"
      ;;
    list-vms)
      cmd_list_vms "$@"
      ;;
    list-backups)
      cmd_list_backups "$@"
      ;;
    doctor)
      doctor "$@"
      ;;
    version)
      echo "$VERSION"
      ;;
    help|-h|--help)
      usage
      ;;
    *)
      err "Unknown command: $cmd"
      usage
      return "$EXIT_USAGE"
      ;;
  esac
}

main "$@"
