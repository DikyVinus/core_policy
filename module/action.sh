cat <<'EOF' > action.sh
#!/system/bin/sh

UID="$(id -u)"
MODDIR="${0%/*}"
LOG="$MODDIR/core_policy.log"

APP_PKG="core.coreshift.policy"
APP_SERVICE="$APP_PKG/.CoreShiftAccessibility"

ROOT_BIN_DIR="/data/data/$APP_PKG/files/bin"
EXT_BIN_DIR="/sdcard/Android/data/$APP_PKG/files/bin"

ROOT_DYNAMIC_LIST="$ROOT_BIN_DIR/core_preload.core"
ROOT_STATIC_LIST="$ROOT_BIN_DIR/core_preload_static.core"

EXT_DYNAMIC_LIST="$EXT_BIN_DIR/core_preload.core"
EXT_STATIC_LIST="$EXT_BIN_DIR/core_preload_static.core"

APK_NAME="CoreShift-release.apk"
APK_PATH=""

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
ENABLED="$(cmd settings get secure accessibility_enabled 2>/dev/null)"
if [ "$ENABLED" = "1" ]; then
    echo "enabled : yes"
else
    echo "enabled : no"
fi

echo
echo "APK:"
for p in \
    "/sdcard/$APK_NAME" \
    "/sdcard/Download/$APK_NAME" \
    "/sdcard/Download/Telegram/$APK_NAME"
do
    if [ -f "$p" ]; then
        APK_PATH="$p"
        break
    fi
done

if [ -n "$APK_PATH" ]; then
    echo "Update found !! 
    echo "Installing Update.."
    cp "$APK_PATH" "$MODDIR/update.apk"
    cmd package install "$MODDIR/update.apk"
    rm "APK_PATH"
fi

if [ "$UID" -eq 0 ]; then
    echo
    echo "Dynamic list:"
    [ -f "$ROOT_DYNAMIC_LIST" ] && cat "$ROOT_DYNAMIC_LIST"

    echo
    echo "Static list:"
    [ -f "$ROOT_STATIC_LIST" ] && cat "$ROOT_STATIC_LIST"
else
    if [ -f "$EXT_DYNAMIC_LIST" ] || [ -f "$EXT_STATIC_LIST" ]; then
        echo
        echo "Dynamic list:"
        [ -f "$EXT_DYNAMIC_LIST" ] && cat "$EXT_DYNAMIC_LIST"

        echo
        echo "Static list:"
        [ -f "$EXT_STATIC_LIST" ] && cat "$EXT_STATIC_LIST"
    fi
fi

echo
echo "Service log:"
[ -f "$LOG" ] && cat "$LOG"
EOF
