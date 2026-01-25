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
SCHED_PID_PROP="debug.core.policy.scheduler.pid"
SCHED_TYPE_PROP="debug.core.policy.scheduler.type"
log() {
    echo "[CorePolicy] $(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"
}

log "service start (uid=$UID)"

# ---- wait for boot ----
while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 2
done
sleep 5
echo > "$LOG"
chmod 0644 "$LOG"
log "boot completed"

# ---- verify ----
VERIFY="$MODDIR/verify.sh"
chmod 0755 "$VERIFY"
if [ ! -x "$VERIFY" ]; then
    exit 1
fi

"$VERIFY" || exit 1


# ---- ABI selection ----
ABI64="$MODDIR/ABI/arm64-v8a"
ABI32="$MODDIR/ABI/armeabi-v7a"

if [ -n "$(getprop ro.product.cpu.abilist64)" ]; then
    RUNDIR="$ABI64"
    log "using arm64 ABI"
else
    RUNDIR="$ABI32"
    log "using arm32 ABI"
fi

# ---- binaries ----
DISCOVERY="$RUNDIR/core_policy_discovery"
PRELOAD_DAEMON="$RUNDIR/core_policy_preload"
DEMOTE_DAEMON="$RUNDIR/core_policy_demote"
PERF_DAEMON="$RUNDIR/core_policy_perf"
RUNTIME="$RUNDIR/core_policy_runtime"

LIBLOCK="$RUNDIR/libcorelock.so"
LIBDEMOTE="$RUNDIR/libcoredemote.so"

DYNAMIC_LIST="$RUNDIR/core_preload.core"
STATIC_LIST="$RUNDIR/core_preload_static.core"

CRONDIR="$MODDIR/cron"
CRONLOG="$CRONDIR/cron.log"
CRONTAB="$CRONDIR/$CRONUSER"

# ---- permissions ----
chmod 0755 \
    "$DISCOVERY" \
    "$PRELOAD_DAEMON" \
    "$DEMOTE_DAEMON" \
    "$PERF_DAEMON" \
    "$RUNTIME" 2>/dev/null

chmod 0644 \
    "$LIBLOCK" \
    "$LIBDEMOTE" \
    "$DYNAMIC_LIST" \
    "$STATIC_LIST" 2>/dev/null

# ---- sanity ----
[ -f "$LIBLOCK" ]   || { log "missing libcorelock"; exit 1; }
[ -f "$LIBDEMOTE" ] || { log "missing libcoredemote"; exit 1; }

# ---- discovery (one-shot) ----
if [ ! -s "$DYNAMIC_LIST" ] || [ ! -s "$STATIC_LIST" ]; then
    log "running discovery"
    "$DISCOVERY"
fi

[ -s "$DYNAMIC_LIST" ] || { log "dynamic list empty, abort"; exit 0; }

# ---- append internal libraries to static list ----
for so in "$RUNDIR"/*.so; do
    [ -f "$so" ] || continue
    grep -qxF "$so" "$STATIC_LIST" 2>/dev/null || {
        echo "$so" >> "$STATIC_LIST"
        log "static lock added: $so"
    }
done


SCHEDULER="none"

# ---- cron fallback (root) ----
if [ "$SCHEDULER" = "none" ] && [ "$UID" -eq 0 ] && command -v busybox >/dev/null; then
    log "trying cron fallback (root)"

    if [ ! -d "$CRONDIR" ]; then
        mkdir -p "$CRONDIR"
        : > "$CRONLOG"

        cat > "$CRONTAB" <<EOT
SHELL=/system/bin/sh
PATH=/system/bin:/system/xbin

*/1 * * * * $PRELOAD_DAEMON
*/1 * * * * $PERF_DAEMON
0   * * * * $DEMOTE_DAEMON
0   0 * * * cmd package bg-dexopt-job
EOT

        chmod 0700 "$CRONDIR"
        chmod 0600 "$CRONTAB"
        chmod 0644 "$CRONLOG"
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
    sleep 1
    pgrep -f "busybox crond.* $CRONDIR" >/dev/null && {
        SCHEDULER="cron"
        log "cron active"
    }
fi

# ---- shell scheduler fallback ----
if [ "$SCHEDULER" = "none" ]; then
    log "using shell scheduler fallback"

    if [ ! -d "$CRONDIR" ]; then
        mkdir -p "$CRONDIR"
        : > "$CRONLOG"

        cat > "$CRONTAB" <<EOT
#!/system/bin/sh
exec >>"$CRONLOG" 2>&1

MIN=0
DAY=\$(date +%d)

while true; do
    sleep 60
    MIN=\$((MIN + 1))
    "$PRELOAD_DAEMON"
    "$PERF_DAEMON"

    if [ "\$MIN" -ge 60 ]; then
        MIN=0
        "$DEMOTE_DAEMON"
    fi

    NOW=\$(date +%d)
    if [ "\$NOW" != "\$DAY" ]; then
        DAY="\$NOW"
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
