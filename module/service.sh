#!/system/bin/sh
# CorePolicy service supervisor

UID="$(id -u)"

if [ "$UID" -eq 0 ]; then
    MODDIR="/data/adb/modules/core_policy"
    CRONUSER="root"
else
    MODDIR="${AXERONDIR}/plugins/core_policy"
    CRONUSER="shell"
fi

LOG="$MODDIR/core_policy.log"
CRONDIR="$MODDIR/cron"
CRONLOG="$CRONDIR/cron.log"
CRONTAB="$CRONDIR/$CRONUSER"

SCHED_PID_PROP="debug.core.policy.scheduler.pid"
SCHED_TYPE_PROP="debug.core.policy.scheduler.type"

log() {
    echo "[CorePolicy] $(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"
}

log "service start (uid=$UID)"

# wait for boot
while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 2
done
sleep 5

# init logs
mkdir -p "$CRONDIR"
: > "$LOG"
: > "$CRONLOG"
chmod 0644 "$LOG" "$CRONLOG"
log "boot completed"

# verify
VERIFY="$MODDIR/verify.sh"
chmod 0755 "$VERIFY"
[ -x "$VERIFY" ] || exit 1
"$VERIFY" || exit 1

# ABI selection
ABI64="$MODDIR/ABI/arm64-v8a"
ABI32="$MODDIR/ABI/armeabi-v7a"

if [ -n "$(getprop ro.product.cpu.abilist64)" ]; then
    RUNDIR="$ABI64"
    log "using arm64 ABI"
else
    RUNDIR="$ABI32"
    log "using arm32 ABI"
fi

# binaries
DISCOVERY="$RUNDIR/core_policy_discovery"
PRELOAD_DAEMON="$RUNDIR/core_policy_preload"
PERF_DAEMON="$RUNDIR/core_policy_perf"
DEMOTE_DAEMON="$RUNDIR/core_policy_demote"
RUNTIME="$RUNDIR/core_policy_runtime"

LIBLOCK="$RUNDIR/libcorelock.so"
LIBDEMOTE="$RUNDIR/libcoredemote.so"

DYNAMIC_LIST="$RUNDIR/core_preload.core"
STATIC_LIST="$RUNDIR/core_preload_static.core"

chmod 0755 \
    "$DISCOVERY" \
    "$PRELOAD_DAEMON" \
    "$PERF_DAEMON" \
    "$DEMOTE_DAEMON" \
    "$RUNTIME" 2>/dev/null

chmod 0644 \
    "$LIBLOCK" \
    "$LIBDEMOTE" \
    "$DYNAMIC_LIST" \
    "$STATIC_LIST" 2>/dev/null

[ -f "$LIBLOCK" ]   || { log "missing libcorelock"; exit 1; }
[ -f "$LIBDEMOTE" ] || { log "missing libcoredemote"; exit 1; }

# discovery
if [ ! -s "$DYNAMIC_LIST" ] || [ ! -s "$STATIC_LIST" ]; then
    log "running discovery"
    "$DISCOVERY"
fi

[ -s "$DYNAMIC_LIST" ] || { log "dynamic list empty, abort"; exit 0; }

# append internal libs
for so in "$RUNDIR"/*.so; do
    [ -f "$so" ] || continue
    grep -qxF "$so" "$STATIC_LIST" 2>/dev/null || {
        echo "$so" >> "$STATIC_LIST"
        log "static lock added: $so"
    }
done

SCHEDULER="none"

# cron fallback (root)
if [ "$UID" -eq 0 ] && command -v busybox >/dev/null; then
    log "trying cron fallback (root)"

    if [ ! -f "$CRONTAB" ]; then
        cat > "$CRONTAB" <<EOT
SHELL=/system/bin/sh
PATH=/system/bin:/system/xbin

*/1 * * * * $PRELOAD_DAEMON
*/1 * * * * $PERF_DAEMON
0   * * * * $DEMOTE_DAEMON
0   0 * * * cmd package bg-dexopt-job
EOT
        chmod 0600 "$CRONTAB"
    fi

    pgrep -f "busybox crond.* $CRONDIR" >/dev/null || \
        busybox crond -f -c "$CRONDIR" -L "$CRONLOG" &

    sleep 1
    CRON_PID="$(pgrep -f "busybox crond.* $CRONDIR" | head -n1)"
    if [ -n "$CRON_PID" ]; then
        setprop "$SCHED_PID_PROP" "$CRON_PID"
        setprop "$SCHED_TYPE_PROP" "cron"
        log "cron scheduler pid=$CRON_PID"
        SCHEDULER="cron"
    fi
fi

# shell fallback
if [ "$SCHEDULER" = "none" ]; then
    log "using shell scheduler fallback"

    if [ ! -f "$CRONTAB" ]; then
        cat > "$CRONTAB" <<EOT
#!/system/bin/sh
exec >>"$CRONLOG" 2>&1

log_run() {
    echo "crond: USER $CRONUSER pid $$ cmd \$1"
}

MIN=0
DAY=\$(date +%d)

while true; do
    sleep 60
    MIN=\$((MIN + 1))

    log_run "$PRELOAD_DAEMON"
    "$PRELOAD_DAEMON"

    log_run "$PERF_DAEMON"
    "$PERF_DAEMON"

    if [ "\$MIN" -ge 60 ]; then
        MIN=0
        log_run "$DEMOTE_DAEMON"
        "$DEMOTE_DAEMON"
    fi

    NOW=\$(date +%d)
    if [ "\$NOW" != "\$DAY" ]; then
        DAY="\$NOW"
        log_run "cmd package bg-dexopt-job"
        cmd package bg-dexopt-job
    fi
done
EOT
        chmod 0755 "$CRONTAB"
    fi

    "$CRONTAB" &
    SHELL_PID="$!"
    setprop "$SCHED_PID_PROP" "$SHELL_PID"
    setprop "$SCHED_TYPE_PROP" "shell"
    log "shell scheduler pid=$SHELL_PID"
    SCHEDULER="shell"
fi

"$PRELOAD_DAEMON" & log "preload pid=$!"
"$PERF_DAEMON"    & log "perf pid=$!"
"$DEMOTE_DAEMON"  & log "demote pid=$!"
"$RUNTIME"        & log "runtime pid=$!"

log "service setup complete (scheduler=$SCHEDULER)"
