#!/usr/bin/env bash
set -Eeuo pipefail

readonly INSTALL_BASE="@INSTALL_BASE@"
readonly APP_BIN="$INSTALL_BASE/app/browsec-desktop"
readonly TARGET_UID="$(id -u)"
source "$INSTALL_BASE/log.sh"

log_event "guardian-start pid=$$ uid=$TARGET_UID"
trap 'log_event "guardian-term pid=$$"; exit 0' TERM
trap 'log_event "guardian-exit pid=$$ status=$?"' EXIT

app_running() {
  local pid
  local executable
  local arguments

  while IFS= read -r pid; do
    [[ -n "$pid" ]] || continue
    executable="$(readlink "/proc/$pid/exe" 2>/dev/null || true)"
    [[ "$executable" == "$APP_BIN" ]] || continue
    arguments="$(tr '\0' '\n' <"/proc/$pid/cmdline" 2>/dev/null || true)"
    if [[ "$arguments" != *$'\n--type='* ]]; then
      APP_PID="$pid"
      return 0
    fi
  done < <(pgrep -u "$TARGET_UID" -x browsec-desktop || true)
  return 1
}

# The launcher starts this service just before Electron. Give it time to
# appear, then watch for a normal exit or a session that kills Electron.
seen=0
APP_PID=""
for ((attempt = 0; attempt < 30; attempt++)); do
  if app_running; then
    seen=1
    log_event "guardian-app-detected pid=$APP_PID"
    break
  fi
  sleep 0.5
done
if ((seen != 1)); then
  log_event "guardian-app-not-found"
  log_snapshot "guardian-app-not-found"
  exit 0
fi

ticks=0
followup_ticks=0
last_wall="$(date +%s)"
while app_running; do
  now_wall="$(date +%s)"
  elapsed=$((now_wall - last_wall))
  if ((elapsed >= 5)); then
    log_event "guardian-wall-gap seconds=$elapsed"
    log_snapshot "after-wall-gap"
    followup_ticks=45
  fi
  last_wall="$now_wall"
  if ((followup_ticks > 0)); then
    if ((followup_ticks % 3 == 0)); then
      log_snapshot "after-wall-gap-followup"
    fi
    followup_ticks=$((followup_ticks - 1))
  elif ((ticks % 15 == 0)); then
    log_snapshot "guardian-heartbeat"
  fi
  ticks=$((ticks + 1))
  sleep 1
done
log_event "guardian-app-gone last-pid=$APP_PID"
log_snapshot "guardian-app-gone"
