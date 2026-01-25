#!/system/bin/sh
exec 2>/dev/null

MODDIR="${0%/*}"
LOG="$MODDIR/core_policy.log"
CRONLOG="$MODDIR/cron/cron.log"

FIRSTPASS_PROP="debug.core.policy.firstpass"
SCHED_PID_PROP="debug.core.policy.sched.pid"
SCHED_TYPE_PROP="debug.core.policy.sched.type"

ABI64="$MODDIR/ABI/arm64-v8a"
ABI32="$MODDIR/ABI/armeabi-v7a"

if [ -n "$(getprop ro.product.cpu.abilist64)" ]; then
    RUNDIR="$ABI64"
else
    RUNDIR="$ABI32"
fi

CRONDIR="$MODDIR/cron"
CRONUSER="$(basename "$(ls "$CRONDIR" 2>/dev/null | head -n1)")"

if [ "$(getprop "$FIRSTPASS_PROP")" != "1" ]; then
    echo "===== CorePolicy ====="
    echo
    cat "$LOG" 2>/dev/null
    echo
    echo "----- cron log (last 10) -----"
    tail -n 10 "$CRONLOG" 2>/dev/null
    echo
    PID="$(getprop "$SCHED_PID_PROP")"
    TYPE="$(getprop "$SCHED_TYPE_PROP")"
    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
        echo "Scheduler alive: $TYPE (pid=$PID)"
    else
        echo "Scheduler not running"
    fi
    setprop "$FIRSTPASS_PROP" 1
    exit 0
fi

PID="$(getprop "$SCHED_PID_PROP")"
TYPE="$(getprop "$SCHED_TYPE_PROP")"

[ -z "$PID" ] && exit 0

if kill -0 "$PID" 2>/dev/null; then
    exit 0
fi

if [ "$TYPE" = "cron" ] && command -v busybox >/dev/null; then
    busybox crond -f -c "$CRONDIR" -L "$CRONLOG" &
    NEWPID="$!"
elif [ "$TYPE" = "shell" ] && [ -x "$CRONDIR/$CRONUSER" ]; then
    "$CRONDIR/$CRONUSER" &
    NEWPID="$!"
else
    exit 0
fi

setprop "$SCHED_PID_PROP" "$NEWPID"
tail -n 5 "$CRONLOG"
exit 0
