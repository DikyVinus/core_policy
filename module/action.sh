#!/system/bin/sh
# SPDX-License-Identifier: Apache-2.0
set -e

MODDIR="${0%/*}"
BIN="$MODDIR/system/bin"
STATUS_LOG="$MODDIR/core_policy.log"
LOCAL_LOG="$MODDIR/localized.log"
XML="$MODDIR/log.xml"

CORESHIFT="$BIN/coreshift"
SERVICE="$MODDIR/service.sh"

UID="$(id -u)"

p() { echo "$@"; }

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

STATUS_TITLE="$(xml_get status_log "System Status")"
LOCAL_TITLE="$(xml_get localized_log "Localization Log")"
SERVICE_TITLE="$(xml_get service_log "Service Activity Log")"

MODE_L="$(xml_get mode_label "MODE:")"
MODE_ROOT="$(xml_get mode_root "root")"
MODE_SHELL="$(xml_get mode_shell "shell")"

BIN_L="$(xml_get binaries_label "Binaries:")"
BIN_OK="$(xml_get binary_present "coreshift : present")"
BIN_MISS="$(xml_get binary_missing "coreshift : missing")"

PROC_L="$(xml_get processes_label "Processes:")"
RUNNING="$(xml_get daemon_running "coreshift daemon : running")"
NOT_RUNNING="$(xml_get daemon_not_running "coreshift daemon : not running")"
RECOVER="$(xml_get attempt_recovery "attempting recovery...")"
SPAWNED="$(xml_get service_spawned "service spawned")"

DYN_L="$(xml_get dump_dynamic "Dynamic list")"
STA_L="$(xml_get dump_static "Static list")"
MISSING="$(xml_get missing "(missing)")"
NO_LOG="$(xml_get no_log "(no log)")"

spawn_service() {
    if command -v busybox >/dev/null 2>&1; then
        busybox setsid sh "$SERVICE" &
    else
        sh "$SERVICE" &
    fi
}

dump() {
    p
    p "$1 ($2):"
    [ -f "$2" ] && cat "$2" || p "$MISSING"
}

p "$STATUS_TITLE"
p

p "$MODE_L"
[ "$UID" -eq 0 ] && p "$MODE_ROOT" || p "$MODE_SHELL"

p
p "$BIN_L"
[ -x "$CORESHIFT" ] && p "$BIN_OK" || p "$BIN_MISS"

p
p "$PROC_L"
PID="$(pidof coreshift 2>/dev/null || true)"

if [ -n "$PID" ]; then
    p "$RUNNING ($PID)"
else
    p "$NOT_RUNNING"
    p "$RECOVER"
    spawn_service
    p "$SPAWNED"
fi

p
if [ "$UID" -ne 0 ]; then
    p
    p "$LOCAL_TITLE"
    [ -f "$LOCAL_LOG" ] && cat "$LOCAL_LOG" || p "$NO_LOG"
fi
p
p "$SERVICE_TITLE"
[ -f "$STATUS_LOG" ] && cat "$STATUS_LOG" || p "$NO_LOG"

dump "$DYN_L" "$BIN/core_preload.core"
dump "$STA_L" "$BIN/core_preload_static.core"
