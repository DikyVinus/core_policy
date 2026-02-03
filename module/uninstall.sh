#!/system/bin/sh

APP_PKG="core.coreshift.policy"
APP_SERVICE="$APP_PKG/.CoreShiftAccessibility"

ENABLED="$(cmd settings get secure enabled_accessibility_services)"

case "$ENABLED" in
    *"$APP_SERVICE"*)
        NEW="$(echo "$ENABLED" | sed "s#:$APP_SERVICE##; s#$APP_SERVICE:##; s#$APP_SERVICE##")"
        cmd settings put secure enabled_accessibility_services "$NEW"
        ;;
esac

if [ "$ENABLED" = "$APP_SERVICE" ]; then
    cmd settings put secure accessibility_enabled 0
fi

cmd package uninstall "$APP_PKG"

