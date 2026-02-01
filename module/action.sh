#!/system/bin/sh

UID="$(id -u)"
MODDIR="${0%/*}"
LOG="$MODDIR/core_policy.log"

APP_PKG="com.coreshift.policy"
APP_SERVICE="$APP_PKG/.TopAppService"

ABI64="$MODDIR/ABI/arm64-v8a"
ABI32="$MODDIR/ABI/armeabi-v7a"

if [ -n "$(getprop ro.product.cpu.abilist64)" ] && [ -d "$ABI64" ]; then
    RUNDIR="$ABI64"
    ABI_NAME="arm64"
else
    RUNDIR="$ABI32"
    ABI_NAME="arm32"
fi

EXE="$RUNDIR/core_policy_exe"
DEMOTE="$RUNDIR/core_policy_demote"
DYNAMIC_LIST="$RUNDIR/core_preload.core"
STATIC_LIST="$RUNDIR/core_preload_static.core"

echo "CorePolicy Status"
echo

echo "Mode:"
echo "app-driven (daemonless)"

echo
echo "UID:"
echo "$UID"

echo
echo "ABI:"
echo "$ABI_NAME"

echo
echo "App:"
if cmd package list packages | grep -q "^package:$APP_PKG$"; then
    echo "installed : yes"
else
    echo "installed : no"
fi

echo
echo "Accessibility:"
ENABLED="$(cmd settings get secure enabled_accessibility_services 2>/dev/null)"
case "$ENABLED" in
    *"$APP_SERVICE"*)
        echo "enabled : yes"
        ;;
    *)
        echo "enabled : no"
        ;;
esac

echo
echo "Binaries:"
[ -x "$EXE" ] && echo "exe    : ok" || echo "exe    : missing"
[ -x "$DEMOTE" ] && echo "demote : ok" || echo "demote : missing"

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
echo "Service log:"
if [ -f "$LOG" ]; then
    cat "$LOG"
else
    echo "(no log found)"
fi

exit 0
