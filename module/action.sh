#!/system/bin/sh
set -e

MODDIR="${0%/*}"
LOG="$MODDIR/core_policy.log"

BIN_DIR="$MODDIR/system/bin"
CORESHIFT_BIN="$BIN_DIR/coreshift"
RUNTIME_BIN="$BIN_DIR/core_policy_runtime"

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
[ -x "$RUNTIME_BIN" ] && echo "core_policy_runtime   : present" || echo "core_policy_runtime   : missing"

echo
echo "Processes:"
DAEMON_PID="$(pidof coreshift || true)"
if [ -n "$DAEMON_PID" ]; then
    echo "coreshift daemon : running ($DAEMON_PID)"
else
    echo "coreshift daemon : not running"
fi

echo
echo "Dynamic list ($DYNAMIC_LIST):"
if [ -f "$DYNAMIC_LIST" ]; then
    cat "$DYNAMIC_LIST"
else
    echo "(missing)"
fi

echo
echo "Static list ($STATIC_LIST):"
if [ -f "$STATIC_LIST" ]; then
    cat "$STATIC_LIST"
else
    echo "(missing)"
fi

echo
echo "Service log:"
if [ -f "$LOG" ]; then
    cat "$LOG"
else
    echo "(no log)"
fi
