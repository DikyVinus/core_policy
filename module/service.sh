#!/system/bin/sh
exec 2>/dev/null

UID="$(id -u)"
MODDIR="${0%/*}"
LOG="$MODDIR/core_policy.log"

APP_PKG="com.CoreShift.core_policy"
APP_ACTIVITY="$APP_PKG/.LauncherActivity"
APK="$MODDIR/CoreShift.apk"

log() {
    echo "[CorePolicy] $(date '+%Y-%m-%d %H:%M:%S') $*" >>"$LOG"
}

while ! pidof com.android.systemui >/dev/null; do
    sleep 8
done

: >"$LOG"
chmod 0644 "$LOG"

log "service start uid=$UID"

VERIFY="$MODDIR/verify.sh"
[ -f "$VERIFY" ] || exit 1
sh "$VERIFY" || exit 1

ABI64="$MODDIR/ABI/arm64-v8a"
ABI32="$MODDIR/ABI/armeabi-v7a"

if [ -n "$(getprop ro.product.cpu.abilist64)" ] && [ -d "$ABI64" ]; then
    RUNDIR="$ABI64"
    log "abi arm64"
else
    RUNDIR="$ABI32"
    log "abi arm32"
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

[ -x "$EXE" ] || exit 1
[ -x "$DEMOTE" ] || exit 1
[ -f "$LIBSHIFT" ] || exit 1

BB="$(command -v resetprop)"
[ -n "$BB" ] || exit 1
BB="$(readlink -f "$BB" || echo "$BB")"
BINDIR="$(dirname "$BB")"

mkdir -p "$BINDIR"
for b in "$DISCOVERY" "$EXE" "$DEMOTE"; do
    ln -sf "$b" "$BINDIR/$(basename "$b")"
done

log "bins linked $BINDIR"

if [ ! -s "$DYNAMIC_LIST" ] || [ ! -s "$STATIC_LIST" ]; then
    log "discovery start"
    "$DISCOVERY"
fi

: >"$RUNDIR/.core_boost.cache"
grep -qxF "$LIBSHIFT" "$STATIC_LIST" || echo "$LIBSHIFT" >>"$STATIC_LIST"

if ! cmd package list packages | grep -q "^package:$APP_PKG$"; then
    log "install app"
    cmd package install -r "$APK" || exit 1
else
    log "app exists"
fi

cmd package grant "$APP_PKG" android.permission.PACKAGE_USAGE_STATS 2>/dev/null
cmd package grant "$APP_PKG" android.permission.FOREGROUND_SERVICE 2>/dev/null
cmd package grant "$APP_PKG" android.permission.FOREGROUND_SERVICE_SPECIAL_USE 2>/dev/null

log "permissions granted"

am start -n "$APP_ACTIVITY" >/dev/null 2>&1

sleep 1
APP_PID="$(pidof "$APP_PKG")"
log "app pid=$APP_PID"

"$RUNTIME" &
"$DEMOTE" &

log "handoff complete app-driven"
exit 0
