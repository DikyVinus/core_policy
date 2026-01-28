#!/system/bin/sh

UID="$(id -u)"

if [ "$UID" -eq 0 ]; then
    MODDIR="/data/adb/modules/core_policy"
    BINDIR="/data/adb/ksu/bin"
    CRONUSER="shell"
else
    MODDIR="${AXERONDIR}/plugins/core_policy"
    BINDIR="$AXERONBIN"
    CRONUSER="shell"
fi

TMPDIR="/data/local/tmp"
CRONDIR="$MODDIR/cron"

LOG="$MODDIR/core_policy.log"
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
mkdir -p "$CRONDIR" "$TMPDIR"
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

### BINARIES (SOURCE)
SRC_EXE="$RUNDIR/core_policy_exe"
SRC_DEMOTE="$RUNDIR/core_policy_demote"
SRC_DISCOVERY="$RUNDIR/core_policy_discovery"
SRC_RUNTIME="$MODDIR/core_policy_runtime"

LIBSHIFT="$RUNDIR/libcoreshift.so"
DYNAMIC_LIST="$RUNDIR/core_preload.core"
STATIC_LIST="$RUNDIR/core_preload_static.core"

chmod 0755 "$SRC_EXE" "$SRC_DEMOTE" "$SRC_DISCOVERY" "$SRC_RUNTIME" 2>/dev/null

### LINK GATE
LINK_GATE="$MODDIR/.linked"
if [ ! -f "$LINK_GATE" ]; then
    mkdir -p "$BINDIR" "$TMPDIR"

    for bin in core_policy_exe core_policy_demote core_policy_discovery; do
        SRC="$RUNDIR/$bin"

        ln -sf "$SRC" "$BINDIR/$bin"
        ln -sf "$SRC" "$TMPDIR/$bin"

        log "linked $bin → $BINDIR and $TMPDIR"
    done

    ln -sf "$SRC_RUNTIME" "$TMPDIR/core_policy_runtime"
    log "linked runtime → $TMPDIR"

    : >"$LINK_GATE"
fi

### REBIND EXEC PATHS (IMPORTANT)
EXE="$TMPDIR/core_policy_exe"
DEMOTE="$TMPDIR/core_policy_demote"
DISCOVERY="$TMPDIR/core_policy_discovery"
RUNTIME="$TMPDIR/core_policy_runtime"

[ -x "$EXE" ] || exit 1
[ -x "$DEMOTE" ] || exit 1

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

*/1 * * * * $EXE
0   * * * * $DEMOTE
0   0 * * * cmd package bg-dexopt-job
EOF
        chmod 0600 "$CRONTAB"
        log "crontab created for $CRONUSER"
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
