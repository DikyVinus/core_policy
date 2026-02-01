#!/system/bin/sh
exec 2>/dev/null

UID="$(id -u)"
MODDIR="${0%/*}"
LOG="$MODDIR/core_policy.log"

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
DAEMON="$RUNDIR/core_policy_daemon"

LIBSHIFT="$RUNDIR/libcoreshift.so"
DYNAMIC_LIST="$RUNDIR/core_preload.core"
STATIC_LIST="$RUNDIR/core_preload_static.core"

chmod 0755 "$DISCOVERY" "$EXE" "$DEMOTE" "$DAEMON"
chmod 0644 "$LIBSHIFT" "$DYNAMIC_LIST" "$STATIC_LIST"

[ -x "$EXE" ] || exit 1
[ -x "$DEMOTE" ] || exit 1
[ -x "$DAEMON" ] || exit 1
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

if pgrep -f "$DAEMON" >/dev/null; then
    log "daemon already running"
else
    "$DAEMON" &
    DAEMON_PID="$!"
    log "daemon started pid=$DAEMON_PID"
fi

log "handoff complete native-daemon"
exit 0
