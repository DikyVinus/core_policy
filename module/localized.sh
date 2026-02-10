#!/system/bin/sh
set -e

MODDIR="${0%/*}"
LOG="$MODDIR/localized.log"
XML="$MODDIR/log.xml"
FILE="$MODDIR/module.prop"
HASH="$FILE.sha256"
GATE="$MODDIR/.localized_done"
[ -f "$DONE_FLAG" ] && exit 0
: >"$LOG"
exec >>"$LOG" 2>&1

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
MSG_VERIFY="$(xml_get verify_hash "[*] verifying sha256")"
MSG_UPDATE="$(xml_get update_desc "[*] updating description")"
MSG_REGEN="$(xml_get regen_hash "[*] regenerating sha256")"
MSG_DONE="$(xml_get done "[✓] done")"
DESC="$(xml_get mod_description "")"

echo "$MSG_VERIFY"

cd "$(dirname "$FILE")"

EXPECTED="$(awk '{print $1}' "$(basename "$HASH")")"
ACTUAL="$(sha256sum "$(basename "$FILE")" | awk '{print $1}')"

[ "$EXPECTED" = "$ACTUAL" ]

echo "$MSG_UPDATE"

ESC_DESC="$(printf '%s\n' "$DESC" | sed 's/[&|]/\\&/g')"
sed -i "s|^description=.*|description=$ESC_DESC|" "$(basename "$FILE")"

echo "$MSG_REGEN"

sha256sum "./$(basename "$FILE")" >"./$(basename "$HASH")"

echo "$MSG_DONE"
touch $GATE
