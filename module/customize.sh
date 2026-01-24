#!/system/bin/sh
# CorePolicy – customize.sh
# User-facing install messages + integrity verification

UID="$(id -u)"

if [ "$UID" -eq 0 ]; then
    MODDIR="/data/adb/modules/core_policy"
    ui_print "• CorePolicy: running as root"
    ui_print "• CorePolicy: module dir = $MODDIR"
else
    MODDIR="${AXERONDIR}/plugins/core_policy"
    ui_print "• CorePolicy: running as non-root"
    ui_print "• CorePolicy: module dir = $MODDIR"
fi

# ============================================================
# Gate 1: hardcoded module.prop verification (trust anchor)
# ============================================================

EXPECTED_PROP_SHA256="187622106a8c5585b885b2c6d3a6525e569e11e5b426159987fcbc644d2f6501"
PROP_FILE="$MODDIR/module.prop"

[ -f "$PROP_FILE" ] || abort "CorePolicy install aborted: module.prop missing"

ACTUAL_PROP_SHA256="$(sha256sum "$PROP_FILE" | awk '{print $1}')"

[ "$ACTUAL_PROP_SHA256" = "$EXPECTED_PROP_SHA256" ] || \
    abort "CorePolicy install aborted: module.prop integrity check failed"

# ============================================================
# Gate 2: payload integrity verification (*.sha256)
# ============================================================

find "$MODDIR" -type f -name '*.sha256' -print0 |
while IFS= read -r -d '' sumfile; do
    target="${sumfile%.sha256}"

    [ -f "$target" ] || abort "CorePolicy install aborted: missing file"

    expected="$(cat "$sumfile")"
    actual="$(sha256sum "$target" | awk '{print $1}')"

    [ "$expected" = "$actual" ] || \
        abort "CorePolicy install aborted: integrity check failed"
done

# ============================================================
# User-facing install messages
# ============================================================

ui_print " "
ui_print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ui_print "        CorePolicy Performance"
ui_print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ui_print " "

ui_print "This module optimizes system performance automatically."
ui_print "No configuration is required."
ui_print " "

ui_print "What CorePolicy does:"
ui_print "• Detects your device RAM and CPU capabilities"
ui_print "• Identifies frequently used apps"
ui_print "• Preloads critical native libraries (.so)"
ui_print "• Boosts foreground and top apps safely"
ui_print "• Uses Android-native scheduling policies"
ui_print " "

ui_print "Smart and adaptive behavior:"
ui_print "• Automatically adjusts to low / mid / high RAM devices"
ui_print "• Never forces performance on background apps"
ui_print "• Avoids system and boot-time slowdowns"
ui_print "• Falls back safely if a feature is unavailable"
ui_print " "

ui_print "Safety guarantees:"
ui_print "• No system files are replaced"
ui_print "• No permanent kernel changes"
ui_print "• No boot blocking"
ui_print "• No continuous background wakelocks"
ui_print " "

ui_print "Compatibility:"
ui_print "• Works on Android 10+"
ui_print "• Supports both root and non-root modes"
ui_print "• Compatible with AOSP and OEM ROMs"
ui_print " "

ui_print "Installation notes:"
ui_print "• First boot may take slightly longer (one-time)"
ui_print "• Performance improves after normal usage"
ui_print "• Changes apply automatically after reboot"
ui_print " "

ui_print "Logs and status:"
ui_print "• Internal logs are minimal by design"
ui_print "• No spam or unnecessary output"
ui_print "• Module operates silently in the background"
ui_print " "

ui_print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ui_print " CorePolicy installed successfully"
ui_print " Reboot to activate"
ui_print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ui_print " "
