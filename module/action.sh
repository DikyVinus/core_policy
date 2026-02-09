#!/system/bin/sh
set -e

MODDIR="${0%/*}"
BIN_DIR="$MODDIR/system/bin"
LOG="$MODDIR/core_policy.log"

CORESHIFT_BIN="$BIN_DIR/coreshift"
SERVICE_SH="$MODDIR/service.sh"

UID="$(id -u)"

echo "CorePolicy Status"
echo

echo "MODE:"
[ "$UID" -eq 0 ] && echo "root" || echo "shell"

echo
echo "Binaries:"
[ -x "$CORESHIFT_BIN" ] && echo "coreshift        : present" || echo "coreshift        : missing"

echo
echo "Processes:"
DAEMON_PID="$(pidof coreshift || true)"

if [ -n "$DAEMON_PID" ]; then
    echo "coreshift daemon : running ($DAEMON_PID)"
else
    echo "coreshift daemon : not running"
    echo "attempting recovery..."

    if [ "$UID" -eq 0 ]; then
        sh "$SERVICE_SH" &
        echo "spawned via service.sh"
    else
        if command -v busybox >/dev/null 2>&1; then
            busybox setsid sh "$SERVICE_SH" &
            echo "spawned via shell"
        else
            sh "$SERVICE_SH" &
            echo "spawned via root"
        fi
    fi
fi

dump_file() {
    echo
    echo "$1 ($2):"
    [ -f "$2" ] && cat "$2" || echo "(missing)"
}

dump_file "Dynamic list" "$BIN_DIR/core_preload.core"
dump_file "Static list"  "$BIN_DIR/core_preload_static.core"

echo
echo "Service log:"
[ -f "$LOG" ] && cat "$LOG" || echo "(no log)"
