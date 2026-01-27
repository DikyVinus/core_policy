#!/system/bin/sh

MODDIR="${0%/*}"
LOG="$MODDIR/core_policy.log"
CRONDIR="$MODDIR/cron"
CRONLOG="$CRONDIR/cron.log"

FIRSTPASS_PROP="debug.core.policy.firstpass"
SCHED_PID_PROP="debug.core.policy.scheduler.pid"
SCHED_TYPE_PROP="debug.core.policy.scheduler.type"

FIRSTPASS="$(getprop "$FIRSTPASS_PROP")"
PID="$(getprop "$SCHED_PID_PROP")"
TYPE="$(getprop "$SCHED_TYPE_PROP")"

echo "===== CorePolicy System Status ====="
echo

echo "--- core_policy.log ---"
if [ -f "$LOG" ]; then
    cat "$LOG"
else
    echo "(core_policy.log not found)"
fi

if [ "$FIRSTPASS" = "1" ]; then
    echo
    echo "--- cronlog ---"
    if [ -f "$CRONLOG" ]; then
        tail -n 10 "$CRONLOG"
    else
        echo "(cron log not found)"
    fi
fi

echo
echo "--- scheduler ---"
echo "pid : ${PID:-}"
echo "type: ${TYPE:-}"

echo
echo "===== END ====="

[ "$FIRSTPASS" != "1" ] && setprop "$FIRSTPASS_PROP" 1

[ -z "$PID" ] && exit 0

if kill -0 "$PID" 2>/dev/null; then
    exit 0
fi

case "$TYPE" in
    cron)
        command -v busybox >/dev/null || exit 0
        busybox crond -f -c "$CRONDIR" -L "$CRONLOG" &
        NEWPID="$!"
        ;;
    shell)
        CRONUSER="$(ls "$CRONDIR" 2>/dev/null | head -n1)"
        [ -n "$CRONUSER" ] && [ -x "$CRONDIR/$CRONUSER" ] || exit 0
        "$CRONDIR/$CRONUSER" &
        NEWPID="$!"
        ;;
    *)
        exit 0
        ;;
esac

setprop "$SCHED_PID_PROP" "$NEWPID"
