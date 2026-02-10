#!/system/bin/sh
set -euo pipefail

MODDIR="${0%/*}"
BIN="$MODDIR/system/bin"
LOG="$MODDIR/core_policy.log"
LOCAL_LOG="$MODDIR/localized.log"
XML="$MODDIR/log.xml"

CORESHIFT="$BIN/coreshift"
SERVICE="$MODDIR/service.sh"

UID="$(id -u)"

p() { echo "$@"; }

xml_get() {
    id="$1"
    lang="$2"
    fallback="$3"

    sec="$(sed -n "/<section id=\"$id\">/,/<\/section>/p" "$XML")" || true
    [ -z "$sec" ] && { echo "$fallback"; return; }

    val="$(echo "$sec" | sed -n "s:.*<$lang>\\(.*\\)</$lang>.*:\\1:p")"
    if [ -z "$val" ]; then
        val="$(echo "$sec" | sed -n "s:.*<en>\\(.*\\)</en>.*:\\1:p")"
    fi

    echo "${val:-$fallback}"
}

# language resolution
LANG_CODE="${1:-${LANG:-en}}"
LANG_CODE="${LANG_CODE%%_*}"
[ "${#LANG_CODE}" -ne 2 ] && LANG_CODE="en"

# localized strings
TITLE="$(xml_get status_title "$LANG_CODE" "CorePolicy Status")"
MODE_L="$(xml_get mode_label "$LANG_CODE" "MODE:")"
MODE_ROOT="$(xml_get mode_root "$LANG_CODE" "root")"
MODE_SHELL="$(xml_get mode_shell "$LANG_CODE" "shell")"

BIN_L="$(xml_get binaries_label "$LANG_CODE" "Binaries:")"
BIN_OK="$(xml_get binary_present "$LANG_CODE" "coreshift : present")"
BIN_MISS="$(xml_get binary_missing "$LANG_CODE" "coreshift : missing")"

PROC_L="$(xml_get processes_label "$LANG_CODE" "Processes:")"
RUNNING="$(xml_get daemon_running "$LANG_CODE" "coreshift daemon : running")"
NOT_RUNNING="$(xml_get daemon_not_running "$LANG_CODE" "coreshift daemon : not running")"
RECOVER="$(xml_get attempt_recovery "$LANG_CODE" "attempting recovery...")"
SPAWNED="$(xml_get service_spawned "$LANG_CODE" "service spawned")"

DYN_L="$(xml_get dump_dynamic "$LANG_CODE" "Dynamic list")"
STA_L="$(xml_get dump_static "$LANG_CODE" "Static list")"
MISSING="$(xml_get missing "$LANG_CODE" "(missing)")"

LOG_L="$(xml_get service_log "$LANG_CODE" "Service log:")"
NO_LOG="$(xml_get no_log "$LANG_CODE" "(no log)")"

# header
p "$TITLE"
p

p "$MODE_L"
[ "$UID" -eq 0 ] && p "$MODE_ROOT" || p "$MODE_SHELL"

p
p "$BIN_L"
[ -x "$CORESHIFT" ] && p "$BIN_OK" || p "$BIN_MISS"

p
p "$PROC_L"
PID="$(pidof coreshift 2>/dev/null || true)"

spawn_service() {
    if command -v busybox >/dev/null 2>&1; then
        busybox setsid sh "$SERVICE" &
    else
        sh "$SERVICE" &
    fi
}

if [ -n "$PID" ]; then
    p "$RUNNING ($PID)"
else
    p "$NOT_RUNNING"
    p "$RECOVER"
    spawn_service
    p "$SPAWNED"
fi

dump() {
    p
    p "$1 ($2):"
    [ -f "$2" ] && cat "$2" || p "$MISSING"
}

dump "$DYN_L" "$BIN/core_preload.core"
dump "$STA_L" "$BIN/core_preload_static.core"

p
p "localized.log:"
[ -f "$LOCAL_LOG" ] && cat "$LOCAL_LOG" || p "$NO_LOG"

p
p "$LOG_L"
[ -f "$LOG" ] && cat "$LOG" || p "$NO_LOG"
