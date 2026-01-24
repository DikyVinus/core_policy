#!/system/bin/sh
# CorePolicy watchdog action
exec 2>/dev/null

MODDIR="${0%/*}"
LOG="$MODDIR/core_policy.log"

ABI64="$MODDIR/ABI/arm64-v8a"
ABI32="$MODDIR/ABI/armeabi-v7a"

if [ -n "$(getprop ro.product.cpu.abilist64)" ]; then
    RUNDIR="$ABI64"
else
    RUNDIR="$ABI32"
fi

BIN_PRELOAD="$RUNDIR/core_policy_preload"
BIN_DEMOTE="$RUNDIR/core_policy_demote"
BIN_RUNTIME="$RUNDIR/core_policy_runtime"

log() {
    echo "[CorePolicy-watchdog] $(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"
}

restart_if_dead() {
    local bin="$1"
    local name

    [ -x "$bin" ] || return

    name="$(basename "$bin")"

    if ! pidof "$name" >/dev/null 2>&1; then
        log "restarting $name"
        "$bin" &
        sleep 1
    fi
}

restart_if_dead "$BIN_PRELOAD"

log "watchdog pass complete"

cat "$LOG" 2>/dev/null