#!/system/bin/sh

MODDIR="${0%/*}"
LOG="$MODDIR/core_policy.log"
READY_FLAG="$MODDIR/.runtime_ready"

CORESHIFT_BIN="$MODDIR/system/bin/coreshift"
: >$LOG
log() {
    echo "[CorePolicy] $(date '+%Y-%m-%d %H:%M:%S') $*" >>"$LOG"
}

while ! pidof com.android.systemui; do
    sleep 8
done

if [ ! -f "$READY_FLAG" ]; then
    ZYGOTE="$(getprop ro.zygote)"
    IS_64=0

    case "$ZYGOTE" in
        zygote64* ) IS_64=1 ;;
    esac

    mkdir -p "$MODDIR/system/bin"

    if [ "$IS_64" -eq 1 ]; then
        if [ -f "$MODDIR/arm64" ]; then
            mv "$MODDIR/arm64" "$CORESHIFT_BIN" && : > "$READY_FLAG"
        fi
    else
        if [ -f "$MODDIR/arm" ]; then
            mv "$MODDIR/arm" "$CORESHIFT_BIN" && : > "$READY_FLAG"
        fi
    fi
    chmod 0644 "$LOG"
    chmod 0755 "$CORESHIFT_BIN"
    chmod 0755 "$RUNTIME_BIN"
fi

log "starting coreshift daemon"
"$CORESHIFT_BIN" daemon &
DAEMON_PID=$!

log "coreshift daemon pid=$DAEMON_PID"

log "core policy services launched (daemon pid=$DAEMON_PID)"
