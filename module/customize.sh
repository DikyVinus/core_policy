#!/system/bin/sh

UID="$(id -u)"

LANG_CODE="$(getprop persist.sys.locale | cut -d- -f1)"
[ -z "$LANG_CODE" ] && LANG_CODE="$(getprop ro.product.locale | cut -d- -f1)"
[ "$LANG_CODE" != "id" ] && LANG_CODE="en"

ui() {
    if [ "$LANG_CODE" = "id" ]; then
        ui_print "$2"
    else
        ui_print "$1"
    fi
}

abort() {
    MSG="$1"

    if [ "$UID" -eq 0 ]; then
        su -lp 2000 -c \
            "cmd notification post CorePolicy \
            \"[CorePolicy] Integrity compromised\" \
            \"$MSG\""
        rm -rf "/data/adb/modules/core_policy"
    else
        cmd notification post CorePolicy \
            "[CorePolicy] Integrity compromised" \
            "$MSG"
        rm -rf "${AXERONDIR}/plugins/core_policy"
    fi

    exit 1
}

if [ "$UID" -eq 0 ]; then
    if [ -d "/data/adb/modules/core_policy" ]; then
        MODDIR="/data/adb/modules/core_policy"
    else
        MODDIR="/data/adb/modules_update/core_policy"
    fi
else
    MODDIR="${AXERONDIR}/plugins/core_policy"
fi

ui "• Module dir: $MODDIR" "• Direktori modul: $MODDIR"

[ -d "$MODDIR" ] || abort "Module directory missing"

PROP_FILE="$MODDIR/module.prop"
PROP_SUM="$MODDIR/module.prop.sha256"

if [ -f "$PROP_FILE" ] && [ -f "$PROP_SUM" ]; then
    expected="$(cat "$PROP_SUM")"
    actual="$(sha256sum "$PROP_FILE" | awk '{print $1}')"
    [ "$expected" = "$actual" ] || abort "module.prop integrity failure"
fi

payload_count=0
only_allowed=1

for f in "$MODDIR"/*; do
    [ -f "$f" ] || continue
    payload_count=$((payload_count + 1))
    name="$(basename "$f")"
    case "$name" in
        module.prop|update)
            ;;
        *)
            only_allowed=0
            ;;
    esac
done

if [ "$only_allowed" -eq 1 ] && [ "$payload_count" -le 2 ]; then
    exit 0
fi

find "$MODDIR" -type f -name '*.sha256' -print0 |
while IFS= read -r -d '' sumfile; do
    target="${sumfile%.sha256}"
    [ -f "$target" ] || abort "Integrity failure: missing file"
    expected="$(cat "$sumfile")"
    actual="$(sha256sum "$target" | awk '{print $1}')"
    [ "$expected" = "$actual" ] || abort "Integrity failure: checksum mismatch"
done

ui_print " "
ui_print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ui_print "        CorePolicy Performance"
ui_print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ui_print " "

ui "This module optimizes system performance automatically." \
   "Modul ini mengoptimalkan performa sistem secara otomatis."
ui "No configuration is required." \
   "Tidak memerlukan konfigurasi."

ui_print " "

ui "What CorePolicy does:" "Fungsi CorePolicy:"
ui "• Detects device RAM and CPU capabilities" \
   "• Mendeteksi kemampuan RAM dan CPU perangkat"
ui "• Identifies frequently used apps" \
   "• Mengidentifikasi aplikasi yang sering digunakan"
ui "• Preloads critical native libraries (.so)" \
   "• Melakukan preload library native penting (.so)"
ui "• Boosts foreground and top apps safely" \
   "• Meningkatkan performa aplikasi foreground secara aman"
ui "• Uses Android-native scheduling policies" \
   "• Menggunakan kebijakan penjadwalan bawaan Android"

ui_print " "

ui "Smart and adaptive behavior:" \
   "Perilaku adaptif dan cerdas:"
ui "• Automatically adjusts to device capabilities" \
   "• Menyesuaikan otomatis dengan kemampuan perangkat"
ui "• Never forces performance on background apps" \
   "• Tidak memaksa performa pada aplikasi latar belakang"
ui "• Avoids system and boot-time slowdowns" \
   "• Menghindari perlambatan sistem dan waktu boot"
ui "• Falls back safely if a feature is unavailable" \
   "• Menggunakan fallback aman jika fitur tidak tersedia"

ui_print " "

ui "Safety guarantees:" "Jaminan keamanan:"
ui "• No system files are replaced" \
   "• Tidak mengganti file sistem"
ui "• No permanent kernel changes" \
   "• Tidak melakukan perubahan kernel permanen"
ui "• No boot blocking" \
   "• Tidak menghambat proses boot"
ui "• No continuous background wakelocks" \
   "• Tidak menahan wakelock latar belakang terus-menerus"

ui_print " "

ui "Compatibility:" "Kompatibilitas:"
ui "• Works on Android 10+" \
   "• Berfungsi pada Android 10 ke atas"
ui "• Supports root and non-root modes" \
   "• Mendukung mode root dan non-root"
ui "• Compatible with AOSP and OEM ROMs" \
   "• Kompatibel dengan ROM AOSP dan OEM"

ui_print " "

ui "Installation notes:" "Catatan instalasi:"
ui "• First boot may take slightly longer (one-time)" \
   "• Boot pertama mungkin sedikit lebih lama (sekali saja)"
ui "• Performance improves after normal usage" \
   "• Performa meningkat setelah penggunaan normal"
ui "• Changes apply automatically after reboot" \
   "• Perubahan diterapkan otomatis setelah reboot"

ui_print " "

ui "Logs and status:" "Log dan status:"
ui "• Minimal internal logging by design" \
   "• Log internal minimal secara desain"
ui "• No spam or unnecessary output" \
   "• Tidak ada output berlebihan"
ui "• Runs silently in the background" \
   "• Berjalan diam-diam di latar belakang"

ui_print " "
ui_print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ui " CorePolicy installed successfully" \
   " CorePolicy berhasil dipasang"
ui " Reboot to activate" \
   " Reboot untuk mengaktifkan"
ui_print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ui_print " "
