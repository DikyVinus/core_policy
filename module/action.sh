#!/system/bin/sh
set -e

MODDIR="${0%/*}"
BIN="$MODDIR/system/bin"
LOG="$MODDIR/core_policy.log"

CORESHIFT="$BIN/coreshift"
SERVICE="$MODDIR/service.sh"

UID="$(id -u)"

p() { echo "$@"; }

p "CorePolicy Status"
p

p "MODE:"
[ "$UID" -eq 0 ] && p "root" || p "shell"

p
p "Binaries:"
[ -x "$CORESHIFT" ] && p "coreshift : present" || p "coreshift : missing"

p
p "Processes:"
PID="$(pidof coreshift 2>/dev/null || true)"

spawn_service() {
    if command -v busybox >/dev/null 2>&1; then
        busybox setsid sh "$SERVICE" &
    else
        sh "$SERVICE" &
    fi
}

if [ -n "$PID" ]; then
    p "coreshift daemon : running ($PID)"
else
    p "coreshift daemon : not running"
    p "attempting recovery..."
    spawn_service
    p "service spawned"
fi

dump() {
    p
    p "$1 ($2):"
    [ -f "$2" ] && cat "$2" || p "(missing)"
}

dump "Dynamic list" "$BIN/core_preload.core"
dump "Static list"  "$BIN/core_preload_static.core"

p
p "Service log:"
[ -f "$LOG" ] && cat "$LOG" || p "(no log)"
