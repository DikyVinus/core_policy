#!/system/bin/sh
set -e

MODDIR="${0%/*}"
BIN_DIR="$MODDIR/system/bin"
LOG="$MODDIR/core_policy.log"

CORESHIFT_BIN="$BIN_DIR/coreshift"
DYNAMIC_LIST="$BIN_DIR/core_preload.core"
STATIC_LIST="$BIN_DIR/core_preload_static.core"

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
if DAEMON_PID="$(pidof coreshift 2>/dev/null)"; then
    echo "coreshift daemon : running ($DAEMON_PID)"
else
    echo "coreshift daemon : not running"
fi

dump_file() {
    echo
    echo "$1 ($2):"
    [ -f "$2" ] && cat "$2" || echo "(missing)"
}

dump_file "Dynamic list" "$DYNAMIC_LIST"
dump_file "Static list"  "$STATIC_LIST"

echo
echo "Service log:"
[ -f "$LOG" ] && cat "$LOG" || echo "(no log)"
