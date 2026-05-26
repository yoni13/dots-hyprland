#!/usr/bin/env bash
set -u

log_file="/tmp/xdg-autostart.log"

log() {
  printf '[%s] %s\n' "$(date '+%F %T')" "$*" >>"$log_file"
}

export XDG_CURRENT_DESKTOP="${XDG_CURRENT_DESKTOP:-Hyprland}"
export XDG_SESSION_DESKTOP="${XDG_SESSION_DESKTOP:-Hyprland}"
export XDG_SESSION_TYPE="${XDG_SESSION_TYPE:-wayland}"

log "starting generated XDG autostart units"
log "env: WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-unset} XDG_CURRENT_DESKTOP=$XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP=$XDG_SESSION_DESKTOP XDG_SESSION_TYPE=$XDG_SESSION_TYPE DISPLAY=${DISPLAY:-unset} DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-unset}"

systemctl --user set-environment \
  XDG_CURRENT_DESKTOP="$XDG_CURRENT_DESKTOP" \
  XDG_SESSION_DESKTOP="$XDG_SESSION_DESKTOP" \
  XDG_SESSION_TYPE="$XDG_SESSION_TYPE" \
  WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-}" \
  DISPLAY="${DISPLAY:-}" \
  DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-}" >>"$log_file" 2>&1

systemctl --user daemon-reload >>"$log_file" 2>&1

mapfile -t autostart_units < <(
  systemctl --user list-dependencies xdg-desktop-autostart.target --plain --no-pager 2>>"$log_file" \
    | sed -n 's/^[[:space:]]*[○●]*[[:space:]]*//; /@autostart\.service$/p'
)

if (( ${#autostart_units[@]} == 0 )); then
  log "no generated autostart units found"
  systemctl --user status xdg-desktop-autostart.target --no-pager >>"$log_file" 2>&1 || true
  exit 1
fi

status=0
for unit in "${autostart_units[@]}"; do
  log "starting $unit"
  if systemctl --user start "$unit" >>"$log_file" 2>&1; then
    log "started $unit"
  else
    unit_status=$?
    log "failed $unit status=$unit_status"
    status=1
  fi
done

exit "$status"
