#!/system/bin/sh
set -euo pipefail

MODDIR="${0%/*}"
XML="$MODDIR/log.xml"

command -v ui_print >/dev/null 2>&1 || ui_print() { echo "$@"; }

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

MSG_START="$(xml_get uninstall_start   "$LANG_CODE" "[CorePolicy] Uninstall: stopping daemon and cleaning symlinks")"
MSG_STOP="$(xml_get daemon_stopped     "$LANG_CODE" "[CorePolicy] coreshift daemon stopped")"
MSG_RM_CS="$(xml_get removed_coreshift "$LANG_CODE" "[CorePolicy] removed %s/coreshift")"
MSG_RM_XML="$(xml_get removed_cli_xml  "$LANG_CODE" "[CorePolicy] removed %s/cli.xml")"
MSG_DONE="$(xml_get uninstall_complete "$LANG_CODE" "[CorePolicy] Uninstall complete")"

ui_print "$MSG_START"

# Kill running coreshift daemons
if pidof coreshift >/dev/null 2>&1; then
    for pid in $(pidof coreshift); do
        kill "$pid" 2>/dev/null || true
    done
    sleep 1
    for pid in $(pidof coreshift); do
        kill -9 "$pid" 2>/dev/null || true
    done
    ui_print "$MSG_STOP"
fi

# Remove only symlinks created during install
for P in ${PATH//:/ }; do
    case "$P" in
        /data/*)
            if [ -L "$P/coreshift" ]; then
                rm -f "$P/coreshift"
                ui_print "$(printf "$MSG_RM_CS" "$P")"
            fi
            if [ -L "$P/cli.xml" ]; then
                rm -f "$P/cli.xml"
                ui_print "$(printf "$MSG_RM_XML" "$P")"
            fi
            ;;
    esac
done

ui_print "$MSG_DONE"
