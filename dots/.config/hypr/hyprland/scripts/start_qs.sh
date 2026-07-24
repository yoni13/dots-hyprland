#!/usr/bin/env bash
set -u

log_file="/tmp/qslog.txt"
qs_config="${1:-${qsConfig:-ii}}"
disk_cache="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell"
ram_cache_root="${QUICKSHELL_RAM_CACHE_ROOT:-/dev/shm/quickshell-$UID}"
ram_cache="$ram_cache_root/cache"
supervisor_lock="${XDG_RUNTIME_DIR:-/tmp}/quickshell-supervisor-${qs_config}.lock"

exec 9>"$supervisor_lock"
if ! flock -n 9; then
  exit 0
fi

log() {
  printf '[%s] %s\n' "$(date '+%F %T')" "$*" >>"$log_file"
}

is_qs_alive() {
  qs -c "$qs_config" list --json 2>/dev/null | jq -e 'length > 0' >/dev/null
}

setup_ram_cache() {
  mkdir -p "$(dirname "$disk_cache")" "$ram_cache"
  chmod 700 "$ram_cache_root" "$ram_cache"

  if [[ -L "$disk_cache" ]]; then
    ln -sfn "$ram_cache" "$disk_cache"
  elif [[ -e "$disk_cache" ]]; then
    local backup="${disk_cache}.disk-backup"
    if [[ -e "$backup" ]]; then
      backup="${backup}.$(date '+%Y%m%d-%H%M%S')"
    fi
    mv "$disk_cache" "$backup"
    ln -s "$ram_cache" "$disk_cache"
    log "start_qs: preserved disk cache at $backup"
  else
    ln -s "$ram_cache" "$disk_cache"
  fi

  log "start_qs: cache=$disk_cache -> $ram_cache"
}

log "start_qs: requested config=$qs_config pid=$$"
log "env: WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-unset} XDG_CURRENT_DESKTOP=${XDG_CURRENT_DESKTOP:-unset} HYPRLAND_INSTANCE_SIGNATURE=${HYPRLAND_INSTANCE_SIGNATURE:-unset}"

setup_ram_cache

# Hyprland can run exec-once before outputs/layers are fully usable.
# Starting qs too early can pass TEST_ALIVE and then crash while creating layer surfaces.
sleep 3

if is_qs_alive; then
  log "start_qs: qs already alive; supervising via IPC"
  while is_qs_alive; do
    sleep 5
  done
  log "start_qs: existing qs disappeared; restarting"
  sleep 3
fi

attempt=0
while true; do
  ((attempt++))
  log "start_qs: launching attempt=$attempt"
  (
    exec 9>&-
    exec systemd-run --user --scope --quiet -p IOWeight=1000 qs -c "$qs_config"
  ) >>"$log_file" 2>&1 &
  qs_pid=$!
  log "start_qs: spawned pid=$qs_pid"

  for _ in 1 2 3 4 5; do
    sleep 1
    if is_qs_alive; then
      log "start_qs: IPC alive after attempt=$attempt; watching for early crash"
      sleep 8
      if kill -0 "$qs_pid" 2>/dev/null && is_qs_alive; then
        log "start_qs: qs stable after attempt=$attempt; supervising pid=$qs_pid"
        wait "$qs_pid"
        status=$?
        log "start_qs: stable qs exited status=$status; restarting after output settles"
        sleep 3
        break
      fi
      if kill -0 "$qs_pid" 2>/dev/null; then
        log "start_qs: IPC disappeared while pid=$qs_pid is still running"
      else
        wait "$qs_pid"
        status=$?
        log "start_qs: pid=$qs_pid crashed after IPC became alive status=$status"
      fi
      break
    fi
    if ! kill -0 "$qs_pid" 2>/dev/null; then
      wait "$qs_pid"
      status=$?
      log "start_qs: pid=$qs_pid exited early status=$status"
      break
    fi
  done

  if kill -0 "$qs_pid" 2>/dev/null; then
    log "start_qs: pid=$qs_pid still running but IPC not ready"
  fi
  sleep 2
done
