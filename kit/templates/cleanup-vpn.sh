#!/usr/bin/env bash
set -Eeuo pipefail

readonly INSTALL_BASE="@INSTALL_BASE@"
readonly TARGET_USER="@TARGET_USER@"
readonly TARGET_UID="$(id -u)"
source "$INSTALL_BASE/log.sh"

[[ "$(id -un)" == "$TARGET_USER" ]] || {
  printf 'Browsec Deck cleanup must run as %s\n' "$TARGET_USER" >&2
  exit 1
}

signal_process() {
  local name="$1"
  local executable="$2"
  local pid actual owner argv0 match

  while IFS= read -r pid; do
    [[ -n "$pid" ]] || continue
    actual="$(readlink "/proc/$pid/exe" 2>/dev/null || printf unreadable)"
    owner="$(stat -c %u "/proc/$pid" 2>/dev/null || printf unknown)"
    match=""
    if [[ "$owner" == "$TARGET_UID" && "$actual" == "$executable" ]]; then
      match="exe"
    elif [[ "$owner" == "$TARGET_UID" && "$actual" == unreadable ]]; then
      # File capabilities can make /proc/PID/exe unreadable to the same user.
      # The app spawns this binary directly, so its first argument is the
      # installed absolute path. Do not log the rest of the command line.
      argv0=""
      IFS= read -r -d '' argv0 < "/proc/$pid/cmdline" 2>/dev/null || true
      [[ "$argv0" == "$executable" ]] && match="argv0"
    fi
    if [[ -n "$match" ]]; then
      if kill -TERM "$pid" 2>/dev/null; then
        log_event "signal name=$name pid=$pid match=$match result=sent"
      else
        log_event "signal name=$name pid=$pid match=$match result=failed"
      fi
    else
      log_event "signal name=$name pid=$pid result=skipped uid=$owner exe=$actual"
    fi
  done < <(pgrep -x "$name" 2>/dev/null || true)
}

# browbox owns the TUN routes and DNS settings. Its SIGTERM handler performs
# cleanup; waiting for it here would delay Desktop session shutdown.
log_event "cleanup-start service-result=${SERVICE_RESULT:-unknown} exit-code=${EXIT_CODE:-unknown} exit-status=${EXIT_STATUS:-unknown}"
log_snapshot "cleanup-before"
signal_process browbox "$INSTALL_BASE/app/resources/xray/browbox"
signal_process browray "$INSTALL_BASE/app/resources/xray/browray"
log_event "cleanup-signals-complete"
