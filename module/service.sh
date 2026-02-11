#!/system/bin/sh
# SPDX-License-Identifier: Apache-2.0
set -e

MODDIR="${0%/*}"
is_root() { [ "$(id -u)" -eq 0 ]; }
BIN="$MODDIR/system/bin"
XML="$MODDIR/log.xml"

LOG="$MODDIR/core_policy.log"
READY_FLAG="$MODDIR/.runtime_ready"
CORESHIFT_BIN="$BIN/coreshift"

SYS_LANG="$(getprop persist.sys.locale | cut -d- -f1)"
[ -n "$SYS_LANG" ] || SYS_LANG="$(getprop ro.product.locale | cut -d- -f1)"

case "$SYS_LANG" in
    en|id|zh|ar|ja|es|hi|pt|ru|de) LANG="$SYS_LANG" ;;
    *) LANG="en" ;;
esac

xml_get() {
    id="$1"
    fallback="$2"

    [ -f "$XML" ] || { echo "$fallback"; return; }

    sed -n "/<section id=\"$id\">/,/<\/section>/p" "$XML" |
        sed -n "s:.*<$LANG>\(.*\)</$LANG>.*:\1:p" |
        head -n1 |
        sed 's/&lt;/</g; s/&gt;/>/g; s/&amp;/\&/g' |
        {
            read -r line || true
            echo "${line:-$fallback}"
        }
}

log() {
    echo "[CorePolicy] $(date '+%Y-%m-%d %H:%M:%S') $*" >>"$LOG"
}

until pidof com.android.systemui >/dev/null 2>&1; do
    sleep 8
done

: >"$LOG"

if ! sh "$MODDIR/localized.sh"; then
    log "$(xml_get log_verify_fail "verification failed, aborting startup")"
    exit 1
fi

if ! sh "$MODDIR/verify.sh"; then
    log "$(xml_get log_verify_fail "verification failed, aborting startup")"
    exit 1
fi

PRIO="ondemand schedutil schedhorizon sugov_ext"

pick_gov() {
    AVAIL="$1"
    for g in $PRIO; do
        echo "$AVAIL" | tr ' ' '\n' | grep -qx "$g" && {
            echo "$g"
            return 0
        }
    done
    return 1
}

if is_root; then
    log "$(xml_get log_gov_scan "scanning cpufreq/devfreq governors")"

    for cpu in /sys/devices/system/cpu/cpu[0-9]*; do
        GOVPATH="$cpu/cpufreq"
        [ -d "$GOVPATH" ] || continue

        AVAIL="$(cat "$GOVPATH/scaling_available_governors" 2>/dev/null)"
        CUR="$(cat "$GOVPATH/scaling_governor" 2>/dev/null)"
        SEL="$(pick_gov "$AVAIL")"

        if [ -n "$SEL" ]; then
            echo "$SEL" > "$GOVPATH/scaling_governor" 2>/dev/null || true
            log "$(xml_get log_cpu_gov_set "cpu governor set") $cpu -> $SEL (was $CUR)"
        else
            log "$(xml_get log_cpu_gov_skip "cpu governor unchanged") $cpu (no match)"
        fi
    done

    for dev in /sys/class/devfreq/*; do
        [ -f "$dev/available_governors" ] || continue

        AVAIL="$(cat "$dev/available_governors" 2>/dev/null)"
        CUR="$(cat "$dev/governor" 2>/dev/null)"
        SEL="$(pick_gov "$AVAIL")"

        if [ -n "$SEL" ]; then
            echo "$SEL" > "$dev/governor" 2>/dev/null || true
            log "$(xml_get log_devfreq_gov_set "devfreq governor set") $dev -> $SEL (was $CUR)"
        else
            log "$(xml_get log_devfreq_gov_skip "devfreq governor unchanged") $dev (no match)"
        fi
    done
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
        cp "$MODDIR/$ARCH" "$CORESHIFT_BIN"
        chmod 0755 "$CORESHIFT_BIN"
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
                        log "$(xml_get log_symlink "symlinked coreshift into") $P"
                        break
                    fi
                    ;;
            esac
        done
    fi
fi

log "$(xml_get log_starting_daemon "starting coreshift daemon")"
"$CORESHIFT_BIN" preload &
"$CORESHIFT_BIN" daemon &
DAEMON_PID=$!

log "$(xml_get log_daemon_pid "coreshift daemon pid=")$DAEMON_PID"
log "$(xml_get log_services_ready "core policy services launched") (daemon pid=$DAEMON_PID)"
