#!/system/bin/sh

UID="$(id -u)"
MODDIR="${0%/*}"
LOG="$MODDIR/core_policy.log"

APP_PKG="core.coreshift.policy"
APP_SERVICE="$APP_PKG/.CoreShiftAccessibility"

ROOT_BIN_DIR="/data/data/$APP_PKG/files/bin"
DYNAMIC_LIST="$ROOT_BIN_DIR/core_preload.core"
STATIC_LIST="$ROOT_BIN_DIR/core_preload_static.core"

echo "CorePolicy Status"
echo
echo "MODE:"
if [ "$UID" -eq 0 ]; then
    echo "root"
else
    echo "shell"
fi
echo
echo "App:"
if cmd package list packages | grep -q "^package:$APP_PKG$"; then
    echo "installed : yes"
else
    echo "installed : no"
fi

PID="$(pidof "$APP_PKG" 2>/dev/null)"
if [ -n "$PID" ]; then
    echo "running   : yes ($PID)"
else
    echo "running   : no"
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

if [ "$UID" -eq 0 ]; then
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
fi

echo
echo "Service log:"
if [ -f "$LOG" ]; then
    cat "$LOG"
else
    echo "(no log found)"
fi
