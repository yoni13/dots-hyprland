#!/usr/bin/env bash

runtime_dir="${XDG_RUNTIME_DIR:-/tmp}"
log_file="$runtime_dir/hyprlock-failsafe.log"

exec 9>"$runtime_dir/hyprlock-failsafe.lock"
flock -n 9 || exit 0

if pgrep -x hyprlock >/dev/null; then
  exit 0
fi

hyprlock
status=$?

if ((status != 0)); then
  printf '[%s] hyprlock exited with status %d; exiting Hyprland\n' \
    "$(date '+%F %T')" "$status" >>"$log_file"

  hyprctl dispatch exit || pkill -TERM -x Hyprland
fi

exit "$status"
