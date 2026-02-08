#!/system/bin/sh

MODDIR="${0%/*}"
LOG="$MODDIR/core_policy.log"
READY_FLAG="$MODDIR/.runtime_ready"

CORESHIFT_BIN="$MODDIR/system/bin/coreshift"
log() {
    echo "[CorePolicy] $(date '+%Y-%m-%d %H:%M:%S') $*" >>"$LOG"
}

while ! pidof com.android.systemui; do
    sleep 8
done
: >$LOG
if [ ! -f "$READY_FLAG" ]; then
    ZYGOTE="$(getprop ro.zygote)"
    case "$ZYGOTE" in
        zygote64*) ARCH=arm64 ;;
        *)         ARCH=arm   ;;
    esac

    mkdir -p "$MODDIR/system/bin"

    if [ -f "$MODDIR/$ARCH" ]; then
        mv "$MODDIR/$ARCH" "$CORESHIFT_BIN" && : >"$READY_FLAG"
        chmod 0755 "$CORESHIFT_BIN"
    fi

    chmod 0644 "$LOG"

    if ! command -v coreshift; then
        IFS=:
        for P in $PATH; do
            case "$P" in
                /data/*)
                    if [ -d "$P" ] && [ -w "$P" ] && [ ! -e "$P/coreshift" ]; then
                        ln -s "$CORESHIFT_BIN" "$P/coreshift" &&
                            log "symlinked coreshift into $P"
                        break
                    fi
                    ;;
            esac
        done
        unset IFS
    fi
fi

log "starting coreshift daemon"
"$CORESHIFT_BIN" preload &
"$CORESHIFT_BIN" daemon &
DAEMON_PID=$!

log "coreshift daemon pid=$DAEMON_PID"

log "core policy services launched (daemon pid=$DAEMON_PID)"
