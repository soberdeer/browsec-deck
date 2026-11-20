# Sourced by the unprivileged launcher, session guard, cleanup and diagnostics.
# Keep this log free of Browsec configuration, command lines and credentials.
BROWSEC_LOG_FILE="$HOME/Desktop/browsec-deck-log"

log_event() {
  local timestamp
  timestamp="$(date -u +'%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || printf 'unknown-time')"
  (
    umask 077
    mkdir -p -- "$HOME/Desktop" || exit 0
    printf '%s %s\n' "$timestamp" "$*" >> "$BROWSEC_LOG_FILE" || true
  ) || true
}

log_snapshot() {
  local label="$1"
  local name pid executable owner state count interface interfaces link_state

  interfaces=""
  for interface in /sys/class/net/browbox*; do
    [[ -e "$interface" ]] || continue
    link_state="$(cat "$interface/operstate" 2>/dev/null || printf unknown)"
    interfaces="${interfaces:+$interfaces,}${interface##*/}:$link_state"
  done
  log_event "snapshot=$label interfaces=${interfaces:-none}"

  for name in browsec-desktop browbox browray; do
    count=0
    while IFS= read -r pid; do
      [[ -n "$pid" ]] || continue
      count=$((count + 1))
      executable="$(readlink "/proc/$pid/exe" 2>/dev/null || printf unreadable)"
      owner="$(stat -c %u "/proc/$pid" 2>/dev/null || printf unknown)"
      state="$(awk '/^State:/ {print $2; exit}' "/proc/$pid/status" 2>/dev/null || true)"
      log_event "process name=$name pid=$pid uid=$owner state=${state:-unknown} exe=$executable"
    done < <(pgrep -x "$name" 2>/dev/null || true)
    ((count > 0)) || log_event "process name=$name count=0"
  done
}
