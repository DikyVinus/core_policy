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

SYS_LANG="$(getprop persist.sys.locale | cut -d- -f1)"
[ -n "$SYS_LANG" ] || SYS_LANG="$(getprop ro.product.locale | cut -d- -f1)"

case "$SYS_LANG" in
    en|id|zh|ar|ja|es|hi|pt|ru|de) LANGUAGE="$SYS_LANG" ;;
    *) LANGUAGE="en" ;;
esac

xml_get() {
    id="$1"
    awk -v id="$id" -v lang="$LANGUAGE" '
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
            exit
        }
    ' "$XML"
}

TITLE="$(xml_get status_title)"
MODE_L="$(xml_get mode_label)"
MODE_ROOT="$(xml_get mode_root)"
MODE_SHELL="$(xml_get mode_shell)"

BIN_L="$(xml_get binaries_label)"
BIN_OK="$(xml_get binary_present)"
BIN_MISS="$(xml_get binary_missing)"

PROC_L="$(xml_get processes_label)"
RUNNING="$(xml_get daemon_running)"
NOT_RUNNING="$(xml_get daemon_not_running)"
RECOVER="$(xml_get attempt_recovery)"
SPAWNED="$(xml_get service_spawned)"

DYN_L="$(xml_get dump_dynamic)"
STA_L="$(xml_get dump_static)"
MISSING="$(xml_get missing)"

LOG_L="$(xml_get service_log)"
NO_LOG="$(xml_get no_log)"

p "$TITLE"
p

p "$MODE_L"
[ "$UID" -eq 0 ] && p "$MODE_ROOT" || p "$MODE_SHELL"

p
p "$BIN_L"
[ -x "$CORESHIFT" ] && p "$BIN_OK" || p "$BIN_MISS"

p
p "localized.log:"
[ -f "$LOCAL_LOG" ] && cat "$LOCAL_LOG" || p "$NO_LOG"

p
p "$LOG_L"
[ -f "$LOG" ] && cat "$LOG" || p "$NO_LOG"

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
