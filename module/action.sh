#!/system/bin/sh

MODDIR="${0%/*}"
LOG="$MODDIR/core_policy.log"
CRONLOG="$MODDIR/cron/cron.log"
CRONDIR="$MODDIR/cron"

FIRSTPASS_PROP="debug.core.policy.firstpass"
SCHED_PID_PROP="debug.core.policy.scheduler.pid"
SCHED_TYPE_PROP="debug.core.policy.scheduler.type"

echo "===== CorePolicy SANITY ====="
echo

echo "--- core_policy.log ---"
if [ -f "$LOG" ]; then
    cat "$LOG"
else
    echo "(core_policy.log not found)"
fi

echo
echo "--- cron.log (last 10) ---"
if [ -f "$CRONLOG" ]; then
    tail -n 10 "$CRONLOG"
else
    echo "(cron.log not found)"
fi

echo
echo "--- properties ---"
FIRSTPASS="$(getprop "$FIRSTPASS_PROP")"
PID="$(getprop "$SCHED_PID_PROP")"
TYPE="$(getprop "$SCHED_TYPE_PROP")"

echo "firstpass: ${FIRSTPASS:-0}"
echo "sched pid: ${PID:-}"
echo "sched type: ${TYPE:-}"

echo
echo "===== END ====="

# mark first pass
[ "$FIRSTPASS" != "1" ] && setprop "$FIRSTPASS_PROP" 1

# nothing to supervise
[ -z "$PID" ] && exit 0

# scheduler still alive
if kill -0 "$PID" 2>/dev/null; then
    exit 0
fi

# restart scheduler
case "$TYPE" in
    cron)
        if command -v busybox >/dev/null; then
            busybox crond -f -c "$CRONDIR" -L "$CRONLOG" &
            NEWPID="$!"
        else
            exit 0
        fi
        ;;
    shell)
        CRONUSER="$(ls "$CRONDIR" 2>/dev/null | head -n1)"
        if [ -n "$CRONUSER" ] && [ -x "$CRONDIR/$CRONUSER" ]; then
            "$CRONDIR/$CRONUSER" &
            NEWPID="$!"
        else
            exit 0
        fi
        ;;
    *)
        exit 0
        ;;
esac

setprop "$SCHED_PID_PROP" "$NEWPID"
exit 0
