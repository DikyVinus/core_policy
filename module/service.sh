#!/system/bin/sh
exec 2>/dev/null
UID="$(id -u)"
MODDIR=${0%/*}
if [ "$UID" -eq 0 ]; then
    CRONUSER="root"
else
    CRONUSER="shell"
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

while ! pidof com.android.systemui ; do
    sleep 8
done

mkdir -p "$CRONDIR"
: >"$LOG"
: >"$CRONLOG"
chmod 0644 "$LOG" "$CRONLOG"

log "service start (uid=$UID)"

VERIFY="$MODDIR/verify.sh"
[ -f "$VERIFY" ] || exit 1
sh "$VERIFY" || exit 1

ABI64="$MODDIR/ABI/arm64-v8a"
ABI32="$MODDIR/ABI/armeabi-v7a"

if [ -n "$(getprop ro.product.cpu.abilist64)" ] && [ -d "$ABI64" ]; then
    RUNDIR="$ABI64"
    log "using arm64 ABI"
else
    RUNDIR="$ABI32"
    log "using arm32 ABI"
fi

DISCOVERY="$RUNDIR/core_policy_discovery"
RUNTIME="$MODDIR/core_policy_runtime"
EXE="$RUNDIR/core_policy_exe"
DEMOTE="$RUNDIR/core_policy_demote"
LIBSHIFT="$RUNDIR/libcoreshift.so"

DYNAMIC_LIST="$RUNDIR/core_preload.core"
STATIC_LIST="$RUNDIR/core_preload_static.core"

chmod 0755 "$DISCOVERY" "$EXE" "$DEMOTE" "$RUNTIME" || true
chmod 0644 "$LIBSHIFT" "$DYNAMIC_LIST" "$STATIC_LIST" || true

[ -x "$EXE" ] || exit 1
[ -x "$DEMOTE" ] || exit 1
[ -f "$LIBSHIFT" ] || exit 1
BB="$(command -v resetprop)"
if [ -n "$BB" ]; then
    BB="$(readlink -f "$BB" || echo "$BB")"
    BINDIR="$(dirname "$BB")"
fi
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

if [ ! -s "$DYNAMIC_LIST" ] || [ ! -s "$STATIC_LIST" ]; then
    log "running discovery"
    "$DISCOVERY"
fi

[ -f "$DYNAMIC_LIST" ] || exit 0

grep -qxF "$LIBSHIFT" "$STATIC_LIST" || echo "$LIBSHIFT" >>"$STATIC_LIST"

if command -v busybox >/dev/null 2>&1; then
    if [ ! -f "$CRONTAB" ]; then
        cat >"$CRONTAB" <<EOF
SHELL=/system/bin/sh
PATH=/system/bin:/system/xbin:$BINDIR

*/1 * * * * $EXE
0   * * * * $DEMOTE
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
else
    SHELL_CRON="$CRONDIR/shell"
    if [ ! -f "$SHELL_CRON" ]; then
        cat >"$SHELL_CRON" <<EOF
#!/system/bin/sh
exec >>"$CRONLOG" 2>&1

MIN=0
DAY=\$(date +%d)

while true; do
    sleep 60
    MIN=\$((MIN + 1))

    $EXE

    if [ "\$MIN" -ge 60 ]; then
        MIN=0
        $DEMOTE
    fi

    NOW=\$(date +%d)
    if [ "\$NOW" != "\$DAY" ]; then
        DAY="\$NOW"
        cmd package bg-dexopt-job
    fi
done
EOF
        chmod 0755 "$SHELL_CRON"
    fi

    "$SHELL_CRON" &
    setprop "$SCHED_PID_PROP" "$!"
    setprop "$SCHED_TYPE_PROP" "shell"
    log "scheduler: shell (pid=$!)"
fi

"$RUNTIME" &
"$DEMOTE" &
log "service setup complete"
exit 0
