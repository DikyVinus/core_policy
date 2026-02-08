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
if [ "$UID" -eq 0 ]; then
    echo "root"
else
    echo "shell"
fi

echo
echo "Binaries:"
if [ -x "$CORESHIFT_BIN" ]; then
    echo "coreshift        : present"
else
    echo "coreshift        : missing"
fi

echo
echo "Processes:"
DAEMON_PID="$(pidof coreshift || true)"

if [ -n "$DAEMON_PID" ]; then
    echo "coreshift daemon : running ($DAEMON_PID)"
else
    echo "coreshift daemon : not running"
    echo "attempting recovery..."

    if echo "$(tr '\0' ' ' </proc/$$/cmdline)" | grep -q axeron; then
        
        busybox setsid sh "$SERVICE_SH" &
        echo "spawned via busybox setsid (axeron)"
    else
    
        sh "$SERVICE_SH"  &
        echo "spawned via service.sh (root)"
    fi
fi

dump_file() {
    echo
    echo "$1 ($2):"
    if [ -f "$2" ]; then
        cat "$2"
    else
        echo "(missing)"
    fi
}

dump_file "Dynamic list" "$BIN_DIR/core_preload.core"
dump_file "Static list"  "$BIN_DIR/core_preload_static.core"

echo
echo "Service log:"
if [ -f "$LOG" ]; then
    cat "$LOG"
else
    echo "(no log)"
fi
