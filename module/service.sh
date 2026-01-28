#!/system/bin/sh

UID="$(id -u)"

if [ "$UID" -eq 0 ]; then
    MODDIR="/data/adb/modules/core_policy"
    BINDIR="/data/adb/ksu/bin"
    CRONUSER="root"
    SU=""
else
    MODDIR="${AXERONDIR}/plugins/core_policy"
    BINDIR="$AXERONBIN"
    CRONUSER="shell"
    SU="/data/adb/ksu/bin/su -c"
fi

LOG="$MODDIR/core_policy.log"
CRONDIR="$MODDIR/cron"
CRONLOG="$CRONDIR/cron.log"
CRONTAB="$CRONDIR/$CRONUSER"

SCHED_PID_PROP="debug.core.policy.scheduler.pid"
SCHED_TYPE_PROP="debug.core.policy.scheduler.type"

log() {
    echo "[CorePolicy] $(date '+%Y-%m-%d %H:%M:%S') $*" >>"$LOG"
}

### WAIT FOR SYSTEM
while :; do
    [ "$(getprop sys.boot_completed)" = "1" ] || { sleep 5; continue; }
    timeout 1 dumpsys usagestats >/dev/null 2>&1 && break
    sleep 5
done

### INIT FS
mkdir -p "$CRONDIR"
: >"$LOG"
: >"$CRONLOG"
chmod 0644 "$LOG" "$CRONLOG"

log "service start (uid=$UID)"

### VERIFY
VERIFY="$MODDIR/verify.sh"
[ -f "$VERIFY" ] || exit 1
sh "$VERIFY" || exit 1

### ABI RESOLUTION
ABI64="$MODDIR/ABI/arm64-v8a"
ABI32="$MODDIR/ABI/armeabi-v7a"

if [ -n "$(getprop ro.product.cpu.abilist64)" ] && [ -d "$ABI64" ]; then
    RUNDIR="$ABI64"
    log "using arm64 ABI"
else
    RUNDIR="$ABI32"
    log "using arm32 ABI"
fi

### BINARIES
DISCOVERY="$RUNDIR/core_policy_discovery"
RUNTIME="$MODDIR/core_policy_runtime"
EXE="$RUNDIR/core_policy_exe"
DEMOTE="$RUNDIR/core_policy_demote"
LIBSHIFT="$RUNDIR/libcoreshift.so"

DYNAMIC_LIST="$RUNDIR/core_preload.core"
STATIC_LIST="$RUNDIR/core_preload_static.core"

chmod 0755 "$DISCOVERY" "$EXE" "$DEMOTE" "$RUNTIME" 2>/dev/null || true
chmod 0644 "$LIBSHIFT" "$DYNAMIC_LIST" "$STATIC_LIST" 2>/dev/null || true

[ -x "$EXE" ] || exit 1
[ -x "$DEMOTE" ] || exit 1
[ -f "$LIBSHIFT" ] || exit 1

### LINK BINARIES
LINK_GATE="$MODDIR/.linked"
if [ ! -f "$LINK_GATE" ]; then
    mkdir -p "$BINDIR"
    for bin in "$DISCOVERY" "$EXE" "$DEMOTE"; do
        name="$(basename "$bin")"
        target="$BINDIR/$name"
        [ -L "$target" ] || ln -s "$bin" "$target"
    done
    : >"$LINK_GATE"
    log "executables linked into $BINDIR"
fi

### DISCOVERY
if [ ! -s "$DYNAMIC_LIST" ] || [ ! -s "$STATIC_LIST" ]; then
    log "running discovery"
    "$DISCOVERY"
fi

[ -s "$DYNAMIC_LIST" ] || exit 0

### ENSURE SELF LIB STATIC-LOCKED
grep -qxF "$LIBSHIFT" "$STATIC_LIST" 2>/dev/null || \
    echo "$LIBSHIFT" >>"$STATIC_LIST"

### CRON 
if command -v busybox >/dev/null 2>&1; then
    if [ ! -f "$CRONTAB" ]; then
        cat >"$CRONTAB" <<EOF
SHELL=/system/bin/sh
PATH=/system/bin:/system/xbin

*/1 * * * * $SU $EXE log
0   * * * * $SU $DEMOTE
0   0 * * * cmd package bg-dexopt-job
EOF
        chmod 0600 "$CRONTAB"
    fi

    pgrep -f "busybox crond.* $CRONDIR" >/dev/null || \
        busybox crond -c "$CRONDIR" -L "$CRONLOG" &

    sleep 1
    CRON_PID="$(pgrep -f "busybox crond.* $CRONDIR" | head -n1)"
    if [ -n "$CRON_PID" ]; then
        setprop "$SCHED_PID_PROP" "$CRON_PID"
        setprop "$SCHED_TYPE_PROP" "cron"
        log "scheduler: cron (pid=$CRON_PID)"
    fi
fi

"$RUNTIME" &
log "service setup complete"
exit 0
