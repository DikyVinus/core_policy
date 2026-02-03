#!/system/bin/sh

MODDIR="${0%/*}"
LOG="$MODDIR/core_policy.log"

APP_PKG="core.coreshift.policy"
APP_ACTIVITY="$APP_PKG/.MainActivity"
APP_ACCESSIBILITY="$APP_PKG/.CoreShiftAccessibility"
APK="$MODDIR/CoreShift-release.apk"

log() {
    echo "[CorePolicy] $(date '+%Y-%m-%d %H:%M:%S') $*" >>"$LOG"
}

while ! pidof com.android.systemui; do
    sleep 8
done

log "boot gate passed"

if cmd package path "$APP_PKG"; then
    cmd activity start -n "$APP_ACTIVITY"
    exit 0
fi

chmod 0644 "$LOG"

[ -f "$APK" ] || exit 1

log "installing apk"
cmd package install -r "$APK" || exit 1

until cmd package path "$APP_PKG"; do
    sleep 1
done

log "install complete"

cmd appops set "$APP_PKG" RUN_IN_BACKGROUND allow
cmd appops set "$APP_PKG" RUN_ANY_IN_BACKGROUND allow
cmd appops set "$APP_PKG" SYSTEM_ALERT_WINDOW allow

log "appops configured"

ENABLED="$(cmd settings get secure enabled_accessibility_services)"

case "$ENABLED" in
    *"$APP_ACCESSIBILITY"*) ;;
    ""|"null")
        cmd settings put secure enabled_accessibility_services "$APP_ACCESSIBILITY"
        ;;
    *)
        cmd settings put secure enabled_accessibility_services "$ENABLED:$APP_ACCESSIBILITY"
        ;;
esac

cmd settings put secure accessibility_enabled 1

log "accessibility enabled"

cmd activity start -n "$APP_ACTIVITY"
log "activity started"
