#!/system/bin/sh
UID="$(id -u)"
CLI_LANG="$1"
command -v ui_print || ui_print() { echo "$@"; }
SYS_LANG="$(getprop persist.sys.locale | cut -d- -f1)"
[ -n "$SYS_LANG" ] || SYS_LANG="$(getprop ro.product.locale | cut -d- -f1)"

case "$CLI_LANG" in
    en|id|zh|ar|ja|es|hi|pt|ru|de) LANG="$CLI_LANG" ;;
    *)
        case "$SYS_LANG" in
            en|id|zh|ar|ja|es|hi|pt|ru|de) LANG="$SYS_LANG" ;;
            *) LANG="en" ;;
        esac
        ;;
esac

ui() { ui_print "$1"; }

curl_fetch() {
    name="$1"
    out="$2"

    command -v curl >/dev/null || return 1
    mkdir -p "$(dirname "$out")" || return 1

    curl -fsSL --max-time 5 \
        "$BASE_URL/$name" \
        -o "$out" || return 1

    [ -s "$out" ]
}

xml_get() {
    [ -n "$LANG_XML" ] || return 1
    sed -n "/<section id=\"$1\">/,/<\/section>/p" "$LANG_XML" |
        sed -n "s:.*<$LANG>\(.*\)</$LANG>.*:\1:p" |
        head -n1
}

say() {
    key="$1"
    fallback="$2"
    text="$(xml_get "$key")"
    [ -n "$text" ] && ui "$text" || ui "$fallback"
}

is_root() {
    [ "$UID" -eq 0 ] && return 0
    [ -w /data/adb ] && return 0
    return 1
}

notify() {
    CMD="cmd notification post CorePolicy \"[CorePolicy] Integrity warning\" \"$1\""
    if is_root; then
        su -lp 2000 -c "$CMD"
    else
        sh -c "$CMD"
    fi
}

parent_cmdline() { tr '\0' ' ' < /proc/$$/cmdline; }

axeron_base_from_path() {
    echo "$PATH" | tr ':' '\n' |
        grep -v tmp |
        sed -n 's|\(.*\/axeron[^/]*\).*|\1|p' |
        head -n1
}
is_axeron() {
    tr '\0' ' ' < /proc/$$/cmdline | grep -q axeron
}

run_bg() {
    if is_root && ! is_axeron; then
        watch_integrity &
    else
        busybox setsid sh -c watch_integrity &
    fi
}

MODDIR=""

if parent_cmdline | grep -q axeron; then
    AXERON_BASE="$(axeron_base_from_path)"
    [ -n "$AXERON_BASE" ] && MODDIR="$AXERON_BASE/plugins/core_policy"
else
    for d in \
    /data/adb/modules/core_policy \
    /data/adb/modules_update/core_policy
do
    [ -d "$d" ] && MODDIR="$d" && break
done
fi

PROP_FILE=""

if [ -f "$MODDIR/module.prop" ]; then
    PROP_FILE="$MODDIR/module.prop"
else
    BASE_DIR="$(dirname "$MODDIR")"
    if [ -f "$BASE_DIR/core_policy/module.prop" ]; then
        PROP_FILE="$BASE_DIR/core_policy/module.prop"
    fi
fi
EXPECTED_SHA256="396804df69a1d129a30c254bd7b0e99305bc270829995c97d6eb990662b446c6"

watch_integrity() {
    end=$((SECONDS + 20))
    while [ "$SECONDS" -lt "$end" ]; do
        [ -d "$MODDIR" ] || notify "Module directory missing"
        [ -x /system/bin/settaskprofile ] || notify "settaskprofile binary missing"

        if [ ! -f "$PROP_FILE" ]; then
            notify "module.prop missing"
        else
            actual="$(sha256sum "$PROP_FILE" | awk '{print $1}')"
            [ "$actual" = "$EXPECTED_SHA256" ] || notify "module.prop checksum mismatch"
        fi
        sleep 1
    done
}

BASE_URL="https://raw.githubusercontent.com/DikyVinus/core_policy/main"

ACTIVE_DIR="$MODDIR"
BASE_DIR="$(dirname "$MODDIR")"
FINAL_DIR="$BASE_DIR/modules/core_policy"

mkdir -p "$ACTIVE_DIR/system/bin" || notify "failed mkdir active system/bin"
mkdir -p "$FINAL_DIR/system/bin"  || notify "failed mkdir final system/bin"

ACTIVE_LANG="$ACTIVE_DIR/lang.xml"
FINAL_LANG="$FINAL_DIR/lang.xml"

ACTIVE_CLI="$ACTIVE_DIR/system/bin/cli.xml"
FINAL_CLI="$FINAL_DIR/system/bin/cli.xml"

if curl_fetch "lang.xml" "$ACTIVE_LANG"; then
    cp -f "$ACTIVE_LANG" "$FINAL_LANG"  || true
    LANG_XML="$ACTIVE_LANG"
fi

if curl_fetch "cli.xml" "$ACTIVE_CLI"; then
    cp -f "$ACTIVE_CLI" "$FINAL_CLI"  || true
fi

case "$MODDIR" in
    */modules_update/*)
        MODDIR="/data/adb/modules/core_policy"
        ;;
esac

run_bg

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
