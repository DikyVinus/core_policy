#!/system/bin/sh
UID="$(id -u)"
MODDIR="${0%/*}"
LOG="$MODDIR/core_policy.log"
CRONDIR="$MODDIR/cron"
CRONLOG="$CRONDIR/cron.log"

FIRSTPASS_PROP="debug.core.policy.firstpass"
SCHED_PID_PROP="debug.core.policy.scheduler.pid"
SCHED_TYPE_PROP="debug.core.policy.scheduler.type"

FIRSTPASS="$(getprop "$FIRSTPASS_PROP")"
SCHED_PID="$(getprop "$SCHED_PID_PROP")"
SCHED_TYPE="$(getprop "$SCHED_TYPE_PROP")"

echo "CorePolicy Status"
echo

echo "Log:"
if [ -f "$LOG" ]; then
    cat "$LOG"
else
    echo "(no log found)"
fi

if [ "$UID" -eq 0 ] && [ "$FIRSTPASS" = "1" ]; then
    echo
    echo "Scheduler log :"
    if [ -f "$CRONLOG" ]; then
        tail -n 10 "$CRONLOG"
    else
        echo "(no scheduler log found)"
    fi
fi

echo
echo "Scheduler:"
echo "type : ${SCHED_TYPE:-unknown}"
echo "pid  : ${SCHED_PID:-}"

[ "$FIRSTPASS" != "1" ] && setprop "$FIRSTPASS_PROP" 1

[ -z "$SCHED_PID" ] && exit 0
[ -z "$SCHED_TYPE" ] && exit 0

if kill -0 "$SCHED_PID" 2>/dev/null; then
    exit 0
fi

case "$SCHED_TYPE" in
    cron)
        command -v busybox >/dev/null || exit 0
        busybox crond -f -c "$CRONDIR" -L "$CRONLOG" &
        NEWPID="$!"
        ;;
    shell)
        CRONUSER="$(ls "$CRONDIR" 2>/dev/null | head -n1)"
        [ -n "$CRONUSER" ] || exit 0
        [ -x "$CRONDIR/$CRONUSER" ] || exit 0
        "$CRONDIR/$CRONUSER" &
        NEWPID="$!"
        ;;
    *)
        exit 0
        ;;
esac

[ -n "$NEWPID" ] && setprop "$SCHED_PID_PROP" "$NEWPID"
exit 0
