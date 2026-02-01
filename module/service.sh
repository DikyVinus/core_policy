cat <<'EOF' > service.sh
#!/system/bin/sh

UID="$(id -u)"
MODDIR="${0%/*}"
LOG="$MODDIR/core_policy.log"

APP_PKG="com.coreshift.policy"
APP_SERVICE="$APP_PKG/.TopAppService"
APK="$MODDIR/CoreShift.apk"
GATE="$MODDIR/.app_ready"

ABI64="$MODDIR/ABI/arm64-v8a"
ABI32="$MODDIR/ABI/armeabi-v7a"

log() {
    echo "[CorePolicy] $(date '+%Y-%m-%d %H:%M:%S') $*" >>"$LOG"
}

while ! pidof com.android.systemui >/dev/null; do
    sleep 5
done

: >"$LOG"
chmod 0644 "$LOG"

log "start uid=$UID"

VERIFY="$MODDIR/verify.sh"
[ -f "$VERIFY" ] && sh "$VERIFY" || log "verify failed"

if [ -n "$(getprop ro.product.cpu.abilist64)" ] && [ -d "$ABI64" ]; then
    RUNDIR="$ABI64"
    log "abi=arm64"
else
    RUNDIR="$ABI32"
    log "abi=arm32"
fi

DISCOVERY="$RUNDIR/core_policy_discovery"
EXE="$RUNDIR/core_policy_exe"
DEMOTE="$RUNDIR/core_policy_demote"
RUNTIME="$MODDIR/core_policy_runtime"

LIBSHIFT="$RUNDIR/libcoreshift.so"
DYNAMIC_LIST="$RUNDIR/core_preload.core"
STATIC_LIST="$RUNDIR/core_preload_static.core"

chmod 0755 "$DISCOVERY" "$EXE" "$DEMOTE" "$RUNTIME"
chmod 0644 "$LIBSHIFT" "$DYNAMIC_LIST" "$STATIC_LIST"

[ -x "$EXE" ] || log "exe missing"
[ -x "$DEMOTE" ] || log "demote missing"
[ -f "$LIBSHIFT" ] || log "lib missing"

BB="$(command -v resetprop)"
if [ -n "$BB" ]; then
    BB="$(readlink -f "$BB" || echo "$BB")"
    BINDIR="$(dirname "$BB")"
    mkdir -p "$BINDIR"
    for b in "$DISCOVERY" "$EXE" "$DEMOTE"; do
        ln -sf "$b" "$BINDIR/$(basename "$b")"
    done
    log "bins linked $BINDIR"
fi

if [ ! -s "$DYNAMIC_LIST" ] || [ ! -s "$STATIC_LIST" ]; then
    log "discovery"
    "$DISCOVERY"
fi

: >"$RUNDIR/.core_boost.cache"
grep -qxF "$LIBSHIFT" "$STATIC_LIST" || echo "$LIBSHIFT" >>"$STATIC_LIST"

[ -f "$GATE" ] && log "app already ready" && exit 0

if ! cmd package list packages | grep -q "^package:$APP_PKG$"; then
    [ -f "$APK" ] || { log "apk missing"; exit 1; }
    log "install app"
    cmd package install -r "$APK" || exit 1
fi

until cmd package path "$APP_PKG" >/dev/null; do
    sleep 1
done

cmd appops set "$APP_PKG" RUN_IN_BACKGROUND allow
cmd appops set "$APP_PKG" RUN_ANY_IN_BACKGROUND allow
cmd appops set "$APP_PKG" SYSTEM_ALERT_WINDOW allow

ENABLED="$(cmd settings get secure enabled_accessibility_services)"

case "$ENABLED" in
    *"$APP_SERVICE"*) ;;
    ""|"null")
        cmd settings put secure enabled_accessibility_services "$APP_SERVICE"
        ;;
    *)
        cmd settings put secure enabled_accessibility_services "$ENABLED:$APP_SERVICE"
        ;;
esac

cmd settings put secure accessibility_enabled 1

"$EXE"
"$RUNTIME" &
"$DEMOTE" &

touch "$GATE"
chmod 0600 "$GATE"

log "handoff complete"
exit 0
EOF
