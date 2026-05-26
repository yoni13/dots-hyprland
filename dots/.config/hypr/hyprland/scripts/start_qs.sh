#!/usr/bin/env bash
set -u

log_file="/tmp/qslog.txt"
qs_config="${1:-${qsConfig:-ii}}"

log() {
  printf '[%s] %s\n' "$(date '+%F %T')" "$*" >>"$log_file"
}

is_qs_alive() {
  qs -c "$qs_config" ipc call TEST_ALIVE >>"$log_file" 2>&1
}

log "start_qs: requested config=$qs_config pid=$$"
log "env: WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-unset} XDG_CURRENT_DESKTOP=${XDG_CURRENT_DESKTOP:-unset} HYPRLAND_INSTANCE_SIGNATURE=${HYPRLAND_INSTANCE_SIGNATURE:-unset}"

if is_qs_alive; then
  log "start_qs: qs already alive"
  exit 0
fi

for attempt in 1 2 3 4 5; do
  log "start_qs: launching attempt=$attempt"
  qs -c "$qs_config" >>"$log_file" 2>&1 &
  qs_pid=$!
  log "start_qs: spawned pid=$qs_pid"

  for _ in 1 2 3 4 5; do
    sleep 1
    if is_qs_alive; then
      log "start_qs: qs alive after attempt=$attempt"
      exit 0
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
done

log "start_qs: failed to confirm qs after retries"
exit 1
