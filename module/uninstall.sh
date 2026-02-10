#!/system/bin/sh
# SPDX-License-Identifier: Apache-2.0
set -e

MODDIR="${0%/*}"
XML="$MODDIR/log.xml"

command -v ui_print >/dev/null 2>&1 || ui_print() { echo "$@"; }

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

MSG_START="$(xml_get uninstall_start   "[CorePolicy] Uninstall: stopping daemon and cleaning symlinks")"
MSG_STOP="$(xml_get daemon_stopped     "[CorePolicy] coreshift daemon stopped")"
MSG_RM_CS="$(xml_get removed_coreshift "[CorePolicy] removed %s/coreshift")"
MSG_RM_XML="$(xml_get removed_cli_xml  "[CorePolicy] removed %s/cli.xml")"
MSG_DONE="$(xml_get uninstall_complete "[CorePolicy] Uninstall complete")"

ui_print "$MSG_START"

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
