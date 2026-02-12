#!/system/bin/sh
# SPDX-License-Identifier: Apache-2.0
exec >/dev/null 2>&1
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
            read line || true
            echo "${line:-$fallback}"
        }
}

log() {
    echo "[CorePolicy] $(date '+%Y-%m-%d %H:%M:%S') $*" >>"$LOG"
}

until pidof com.android.systemui ; do
    sleep 8
done

echo >"$LOG"

if ! is_root; then
    sh "$MODDIR/localized.sh" || exit 1
fi

if ! sh "$MODDIR/verify.sh"; then
    log "$(xml_get log_verify_fail "verification failed, aborting startup")"
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
        cp "$MODDIR/$ARCH" "$CORESHIFT_BIN"
        chmod 0755 "$CORESHIFT_BIN"
        : >"$READY_FLAG"
    fi

    chmod 0644 "$LOG"

    if ! which coreshift ; then
    OLDIFS="$IFS"
    IFS=:
    for P in $PATH; do
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
    IFS="$OLDIFS"
fi
fi

log "$(xml_get log_starting_daemon "starting coreshift daemon")"
"$CORESHIFT_BIN" preload &
"$CORESHIFT_BIN" daemon &
DAEMON_PID=$!

log "$(xml_get log_daemon_pid "coreshift daemon pid=")$DAEMON_PID"
log "$(xml_get log_services_ready "core policy services launched") (daemon pid=$DAEMON_PID)"

PRIO="schedutil simple_ondemand schedhorizon sugov_ext"

pick_gov() {
    AVAIL="$1"
    for g in $PRIO; do
        for x in $AVAIL; do
            [ "$x" = "$g" ] && {
                echo "$g"
                return 0
            }
        done
    done
    return 1
}

if is_root; then
    log "$(xml_get log_gov_scan "scanning cpufreq/devfreq governors")"

    for cpu in /sys/devices/system/cpu/cpu[0-9]*; do
        GOVPATH="$cpu/cpufreq"
        [ -d "$GOVPATH" ] || continue

        AVAIL="$(cat "$GOVPATH/scaling_available_governors")"
        CUR="$(cat "$GOVPATH/scaling_governor")"
        SEL="$(pick_gov "$AVAIL")"

        if [ -n "$SEL" ] && [ "$SEL" != "$CUR" ]; then
            echo "$SEL" > "$GOVPATH/scaling_governor" || true
            log "$(xml_get log_cpu_gov_set "cpu governor set") $cpu -> $SEL ($(xml_get log_was "was") $CUR)"
        else
            log "$(xml_get log_current "current") $cpu -> $CUR"
        fi
    done

    for dev in /sys/class/devfreq/*; do
        [ -f "$dev/available_governors" ] || continue

        AVAIL="$(cat "$dev/available_governors")"
        CUR="$(cat "$dev/governor" )"
        SEL="$(pick_gov "$AVAIL")"

        if [ -n "$SEL" ] && [ "$SEL" != "$CUR" ]; then
            echo "$SEL" > "$dev/governor" || true
            log "$(xml_get log_devfreq_gov_set "devfreq governor set") $dev -> $SEL ($(xml_get log_was "was") $CUR)"
        else
            log "$(xml_get log_current "current") $dev -> $CUR"
        fi
    done
fi

BLK_PRIO="mq-deadline kyber bfq deadline none noop"

pick_blk() {
    AVAIL=`echo "$1" | tr '[]' ' '`
    for g in $BLK_PRIO; do
        for x in $AVAIL; do
            [ "$x" = "$g" ] && {
                echo "$g"
                return 0
            }
        done
    done
    return 1
}

if is_root; then
    log "$(xml_get log_blk_scan "scanning block schedulers")"

    for q in /sys/block/*/queue; do
        dev="${q#/sys/block/}"
        dev="${dev%/queue}"

        case "$dev" in
            loop*|ram*|zram*|fd*) continue ;;
        esac

        [ -f "$q/io_timeout" ] || continue
        [ -f "$q/scheduler" ] || continue

        AVAIL="$(cat "$q/scheduler")"
        CUR="$(echo "$AVAIL" | sed -n 's/.*\[\(.*\)\].*/\1/p')"
        SEL="$(pick_blk "$AVAIL")"

        if [ -n "$SEL" ] && [ "$SEL" != "$CUR" ]; then
            echo "$SEL" > "$q/scheduler" || true
            log "$(xml_get log_blk_set "block scheduler set") ${q%/queue} -> $SEL ($(xml_get log_was "was") $CUR)"
        else
            log "$(xml_get log_current "current") ${q%/queue} -> $CUR"
        fi
    done
fi

if is_root; then

write() {
    path="$1"
    val="$2"
    [ -e "$path" ] || return

    cur="$(cat "$path" || true)"
    if [ "$cur" = "$val" ]; then
        log "$(xml_get log_current "current") $path -> $cur"
        return
    fi

    echo "$val" > "$path" || return
    log "$(xml_get log_value_set "set") $path -> $val ($(xml_get log_was "was") $cur)"
}

LITTLE=""
BIG=""
for c in /sys/devices/system/cpu/cpu[0-9]*; do
    id="${c##*cpu}"
    cap="$(cat "$c/cpu_capacity")"
    [ -z "$cap" ] && continue
    if [ "$cap" -lt 512 ]; then
        LITTLE="$LITTLE $id"
    else
        BIG="$BIG $id"
    fi
done

range_from_list() {
    min=""
    max=""
    for i in $1; do
        [ -z "$min" ] && min="$i"
        max="$i"
    done
    [ -n "$min" ] && echo "$min-$max"
}

LITTLE_RANGE="$(range_from_list "$LITTLE")"
ALL_RANGE="$(range_from_list "$LITTLE $BIG")"

write /dev/cpuctl/background/cpu.uclamp.min 0
write /dev/cpuctl/background/cpu.uclamp.max 10
write /dev/cpuctl/background/cpu.uclamp.latency_sensitive 0

write /dev/cpuctl/system-background/cpu.uclamp.min 0
write /dev/cpuctl/system-background/cpu.uclamp.max 15
write /dev/cpuctl/system-background/cpu.uclamp.latency_sensitive 0

write /dev/cpuctl/foreground/cpu.uclamp.min 0
write /dev/cpuctl/foreground/cpu.uclamp.max 25
write /dev/cpuctl/foreground/cpu.uclamp.latency_sensitive 1

write /dev/cpuctl/top-app/cpu.uclamp.min 20
write /dev/cpuctl/top-app/cpu.uclamp.max 100
write /dev/cpuctl/top-app/cpu.uclamp.latency_sensitive 1

[ -n "$LITTLE_RANGE" ] && {
    write /dev/cpuset/background/cpus "$LITTLE_RANGE"
    write /dev/cpuset/system-background/cpus "$LITTLE_RANGE"
}

[ -n "$ALL_RANGE" ] && {
    write /dev/cpuset/foreground/cpus "$ALL_RANGE"
    write /dev/cpuset/top-app/cpus "$ALL_RANGE"
}

write /dev/cpuset/background/sched_load_balance 0
write /dev/cpuset/system-background/sched_load_balance 0
write /dev/cpuset/foreground/sched_load_balance 1
write /dev/cpuset/top-app/sched_load_balance 1

write /proc/sys/kernel/sched_migration_cost_ns 5000000

for p in /sys/devices/system/cpu/cpufreq/policy*/schedutil; do
    [ -d "$p" ] || continue
    write "$p/up_rate_limit_us" 500
    write "$p/down_rate_limit_us" 20000
done

for q in /sys/block/*/queue; do
    dev="${q#/sys/block/}"
    dev="${dev%/queue}"

    case "$dev" in
        loop*|ram*|zram*|fd*) continue ;;
    esac

    [ -f "$q/io_timeout" ] || continue

    write "$q/read_ahead_kb" 128
    write "$q/nr_requests" 64
done

write /sys/block/zram0/max_comp_streams 2
write /sys/kernel/mm/transparent_hugepage/enabled madvise
write /sys/kernel/mm/transparent_hugepage/defrag defer
write /proc/sys/vm/watermark_scale_factor 10
write /proc/sys/vm/page-cluster 0

fi

CMD=/system/bin/cmd
PROTECT_PKGS="
android
com.android.systemui
com.android.providers.telephony
com.android.providers.media
com.android.providers.settings
com.android.bluetooth
com.android.settings
com.android.launcher3
com.android.permissioncontroller
com.google.android.gms
com.google.android.gsf
"

for pkg in $($CMD package list packages -s | sed 's/package://'); do
    case " $PROTECT_PKGS " in
        *" $pkg "*) continue ;;
    esac

    $CMD activity make-uid-idle --user 0 "$pkg"
    $CMD sensorservice set-uid-state "$pkg" idle
done
