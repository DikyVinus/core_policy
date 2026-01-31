#!/system/bin/sh
UID="$(id -u)"
MODDIR="${0%/*}"
LOG="$MODDIR/core_policy.log"

APP_PKG="com.CoreShift.core_policy"

ABI64="$MODDIR/ABI/arm64-v8a"
ABI32="$MODDIR/ABI/armeabi-v7a"

if [ -n "$(getprop ro.product.cpu.abilist64)" ] && [ -d "$ABI64" ]; then
    RUNDIR="$ABI64"
    ABI_NAME="arm64"
else
    RUNDIR="$ABI32"
    ABI_NAME="arm32"
fi

DYNAMIC_LIST="$RUNDIR/core_preload.core"
STATIC_LIST="$RUNDIR/core_preload_static.core"

APP_PID="$(pidof "$APP_PKG")"

echo "CorePolicy Status"
echo

echo "App:"
if [ -n "$APP_PID" ]; then
    echo "state : running"
    echo "pid   : $APP_PID"
else
    echo "state : not running"
    echo "pid   : -"
fi

echo
echo "ABI:"
echo "$ABI_NAME"

echo
echo "Dynamic list:"
if [ -f "$DYNAMIC_LIST" ]; then
    cat "$DYNAMIC_LIST"
else
    echo "(missing)"
fi

echo
echo "Static list:"
if [ -f "$STATIC_LIST" ]; then
    cat "$STATIC_LIST"
else
    echo "(missing)"
fi

echo
echo "Log:"
if [ -f "$LOG" ]; then
    cat "$LOG"
else
    echo "(no log found)"
fi

exit 0
