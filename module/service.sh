#!/system/bin/sh

MODDIR="${0%/*}"
BIN="$MODDIR/system/bin"
XML="$BIN/log.xml"

LOG="$MODDIR/core_policy.log"
READY_FLAG="$MODDIR/.runtime_ready"
CORESHIFT_BIN="$BIN/coreshift"

xml_get() {
    id="$1"
    lang="${LANGUAGE:-en}"
    awk -v id="$id" -v lang="$lang" '
        $0 ~ "<section id=\""id"\">" { f=1; next }
        f && $0 ~ "</section>" { exit }
        f && $0 ~ "<"lang">" {
            sub(".*<"lang">","")
            sub("</.*","")
            print
            exit
        }
        f && $0 ~ "<en>" {
            sub(".*<en>","")
            sub("</.*","")
            print
        }
    ' "$XML"
}

log() {
    echo "[CorePolicy] $(date '+%Y-%m-%d %H:%M:%S') $*" >>"$LOG"
}

# wait for system UI
until pidof com.android.systemui >/dev/null 2>&1; do
    sleep 8
done

: >"$LOG"

if ! sh "$MODDIR/localized.sh"; then
    log "$(xml_get log_verify_fail)"
    exit 1
fi

# verification
if ! sh "$MODDIR/verify.sh"; then
    log "$(xml_get log_verify_fail)"
    exit 1
fi

if [ ! -f "$READY_FLAG" ]; then
    mkdir -p "$BIN"

    ABI="$(getprop ro.product.cpu.abi)"

    case "$ABI" in
        arm64-v8a) ARCH=arm64 ;;
        armeabi-v7a|armeabi) ARCH=arm ;;
        *) ARCH=arm ;;
    esac

    if [ -f "$MODDIR/$ARCH" ]; then
        cp "$MODDIR/$ARCH" "$CORESHIFT_BIN" &&
        chmod 0755 "$CORESHIFT_BIN" &&
        : >"$READY_FLAG"
    fi

    chmod 0644 "$LOG"

    if ! command -v coreshift >/dev/null 2>&1; then
        for P in ${PATH//:/ }; do
            case "$P" in
                /data/*)
                    if [ -d "$P" ] && [ -w "$P" ] && [ ! -e "$P/coreshift" ]; then
                        ln -s "$CORESHIFT_BIN" "$P/coreshift"
                        ln -s "$BIN/cli.xml" "$P/cli.xml"
                        log "$(xml_get log_symlink) $P"
                        break
                    fi
                    ;;
            esac
        done
    fi
fi

log "$(xml_get log_starting_daemon)"
"$CORESHIFT_BIN" preload &
"$CORESHIFT_BIN" daemon &
DAEMON_PID=$!

log "$(xml_get log_daemon_pid)$DAEMON_PID"
log "$(xml_get log_services_ready) (daemon pid=$DAEMON_PID)"
