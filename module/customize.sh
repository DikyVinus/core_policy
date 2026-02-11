#!/system/bin/sh
# SPDX-License-Identifier: Apache-2.0
exec 2>/dev/null

UID="$(id -u)"

command -v ui_print >/dev/null 2>&1 || ui_print() { echo "$@"; }
ui() { ui_print "$1"; }

SYS_LANG="$(getprop persist.sys.locale | cut -d- -f1)"
[ -n "$SYS_LANG" ] || SYS_LANG="$(getprop ro.product.locale | cut -d- -f1)"

case "$SYS_LANG" in
    en|id|zh|ar|ja|es|hi|pt|ru|de) LANG="$SYS_LANG" ;;
    *) LANG="en" ;;
esac

is_root() { [ "$UID" -eq 0 ] || [ -w /data/adb ]; }

axeron_base() {
    OLDIFS="$IFS"
    IFS=:
    for p in $PATH; do
        case "$p" in
            */axeron*)
                IFS="$OLDIFS"
                echo "${p%%/axeron*}/axeron"
                return 0
            ;;
        esac
    done
    IFS="$OLDIFS"

    if [ -n "$AXERONDIR" ] && [ -d "$AXERONDIR" ]; then
        echo "$AXERONDIR"
        return 0
    fi

    return 1
}

AXERON_BASE="$(axeron_base)"

if [ -n "$AXERON_BASE" ]; then
    MODDIR="$AXERON_BASE/plugins/core_policy"
    UPDATE_DIR=""
elif is_root; then
    MODDIR="/data/adb/modules/core_policy"
    UPDATE_DIR="/data/adb/modules_update/core_policy"
else
    exit 1
fi

EXPECTED_SHA256="396804df69a1d129a30c254bd7b0e99305bc270829995c97d6eb990662b446c6"

PROP_FILE=""
[ -f "$UPDATE_DIR/module.prop" ] && PROP_FILE="$UPDATE_DIR/module.prop"
[ -z "$PROP_FILE" ] && [ -f "$MODDIR/module.prop" ] && PROP_FILE="$MODDIR/module.prop"

notify() {
    cmd="cmd notification post CorePolicy \"[CorePolicy] Integrity warning\" \"$1\""
    is_root && su -lp 2000 -c "$cmd" || sh -c "$cmd"
}

watch_integrity() {
    i=0
    while [ "$i" -lt 20 ]; do
        [ -d "$MODDIR" ] || notify "Module directory missing"
        [ -x /system/bin/settaskprofile ] || notify "settaskprofile binary missing"

        if [ -f "$PROP_FILE" ]; then
            cur=`sha256sum "$PROP_FILE" | awk '{print $1}'`
            [ "$cur" = "$EXPECTED_SHA256" ] || notify "module.prop checksum mismatch"
        else
            notify "module.prop missing"
        fi

        i=`expr "$i" + 1`
        sleep 1
    done
}

if command -v busybox >/dev/null 2>&1; then
    busybox setsid sh -c 'watch_integrity' &
else
    watch_integrity &
fi

BASE_URL="https://raw.githubusercontent.com/DikyVinus/core_policy/main"
LANG_XML="$MODDIR/lang.xml"
UPD_LANG="$UPDATE_DIR/lang.xml"

if command -v curl >/dev/null 2>&1; then
    mkdir -p "$MODDIR"
    curl -fsSL --max-time 5 "$BASE_URL/lang.xml" -o "$LANG_XML" &&
        [ -n "$UPDATE_DIR" ] && cp -f "$LANG_XML" "$UPD_LANG"
fi

LANG_SHA="$LANG_XML.sha256"
UPD_LANG_SHA="$UPD_LANG.sha256"

if [ -f "$LANG_XML" ]; then
    DIR=`dirname "$LANG_XML"`
BASE=`basename "$LANG_XML"`
HASHBASE=`basename "$LANG_SHA"`

cd "$DIR" || exit 1
sha256sum "$BASE" >"$HASHBASE"

    if [ -n "$UPDATE_DIR" ] && [ -f "$LANG_SHA" ]; then
        cp -f "$LANG_SHA" "$UPD_LANG_SHA"
    fi
fi

xml_get() {
    [ -f "$LANG_XML" ] || return 1
    sed -n "/<section id=\"$1\">/,/<\/section>/p" "$LANG_XML" |
        sed -n "s:.*<$LANG>\(.*\)</$LANG>.*:\1:p" |
        head -n1
}

say() {
    t=`xml_get "$1"`
    if [ -n "$t" ]; then
        ui "$t"
    else
        ui "$2"
    fi
}

ui " "
ui "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
say header "CorePolicy Performance"
ui "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ui " "

say moddir "• Module directory:"
ui "$MODDIR"

say intro "This module optimizes system performance automatically."
say no_config "No configuration is required."

ui " "
say what_title "What CorePolicy does:"
say detect_hw "• Detects device RAM and CPU capabilities"
say identify_apps "• Identifies frequently used apps"
say preload_libs "• Preloads critical native libraries (.so)"
say boost_apps "• Boosts foreground and top apps safely"
say scheduler "• Uses Android-native scheduling policies"

ui " "
say adaptive_title "Smart and adaptive behavior:"
say adaptive_auto "• Automatically adjusts to device capabilities"
say adaptive_no_bg "• Never forces performance on background apps"
say adaptive_safe "• Falls back safely if a feature is unavailable"

ui " "
say safety_title "Safety guarantees:"
say safety_sys "• No system files are replaced"
say safety_kernel "• No permanent kernel changes"
say safety_boot "• No boot blocking"
say safety_wakelock "• No continuous background wakelocks"

ui " "
say compat_title "Compatibility:"
say compat_android "• Works on Android 10+"
say compat_root "• Supports root and non-root modes"
say compat_rom "• Compatible with AOSP and OEM ROMs"

ui " "
ui "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
say installed "CorePolicy installed successfully"
say reboot "Reboot to activate"
ui "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ui " "
