#!/usr/bin/env bash
set -u

runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
log_file="$runtime_dir/hyprlock-failsafe.log"
instance="${HYPRLAND_INSTANCE_SIGNATURE:-unknown}"
instance_key="${instance//[^[:alnum:]_.-]/_}"
lock_file="$runtime_dir/hyprlock-failsafe-$instance_key.lock"

fail_closed() {
  printf '[%s] %s; terminating the current session\n' \
    "$(date '+%F %T')" "$1" >>"$log_file"

  hyprctl dispatch exit >/dev/null 2>&1 && return
  if [[ -n "${XDG_SESSION_ID:-}" ]]; then
    loginctl terminate-session "$XDG_SESSION_ID" >/dev/null 2>&1 && return
  fi
  return 1
}

if [[ ! -d "$runtime_dir" || ! -O "$runtime_dir" ]]; then
  hyprctl dispatch exit >/dev/null 2>&1
  exit 1
fi

exec 9>"$lock_file" || {
  fail_closed "could not create the session lock file"
  exit 1
}
flock -n 9 || exit 0

hyprlock_running_for_instance() {
  local pid
  while read -r pid; do
    [[ -r "/proc/$pid/environ" ]] || continue
    if tr '\0' '\n' <"/proc/$pid/environ" \
      | grep -Fqx -- "HYPRLAND_INSTANCE_SIGNATURE=$instance"; then
      return 0
    fi
  done < <(pgrep -u "$UID" -x hyprlock 2>/dev/null)
  return 1
}

config_file="${XDG_CONFIG_HOME:-$HOME/.config}/illogical-impulse/config.json"
use_hyprlock=true
if command -v jq >/dev/null 2>&1 && [[ -r "$config_file" ]]; then
  configured_lock=$(jq -r '.lock.useHyprlock // true' "$config_file" 2>/dev/null || true)
  [[ "$configured_lock" == "false" ]] && use_hyprlock=false
fi

if [[ "$use_hyprlock" == "false" ]]; then
  qs_config="${qsConfig:-ii}"
  if ! qs -c "$qs_config" ipc call lock activate >/dev/null 2>&1; then
    fail_closed "could not request the Quickshell session lock"
    exit 1
  fi

  for _ in {1..50}; do
    if [[ "$(qs -c "$qs_config" ipc prop get lock secure 2>/dev/null)" == "true" ]]; then
      exit 0
    fi
    sleep 0.1
  done

  fail_closed "Quickshell did not confirm a secure session lock"
  exit 1
fi

if hyprlock_running_for_instance; then
  exit 0
fi

hyprlock
status=$?

if ((status != 0)); then
  fail_closed "hyprlock exited with status $status"
fi

exit "$status"
