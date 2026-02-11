#!/system/bin/sh
# SPDX-License-Identifier: Apache-2.0
set -e

MODDIR="${0%/*}"
LOG="$MODDIR/localized.log"
XML="$MODDIR/log.xml"
FILE="$MODDIR/module.prop"
HASH="$FILE.sha256"
GATE="$MODDIR/.localized_done"

[ -f "$GATE" ] && exit 0

echo >"$LOG"
exec >>"$LOG" 2>&1

SYS_LANG=`getprop persist.sys.locale | cut -d- -f1`
[ -n "$SYS_LANG" ] || SYS_LANG=`getprop ro.product.locale | cut -d- -f1`

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
        read line
        [ -n "$line" ] && echo "$line" || echo "$fallback"
    }
}

MSG_VERIFY=`xml_get verify_hash "[*] verifying sha256"`
MSG_UPDATE=`xml_get update_desc "[*] updating description"`
MSG_REGEN=`xml_get regen_hash "[*] regenerating sha256"`
MSG_DONE=`xml_get done "[done]"`
DESC=`xml_get mod_description ""`

echo "$MSG_VERIFY"

DIRNAME=`dirname "$FILE"`
BASENAME=`basename "$FILE"`
HASHBASE=`basename "$HASH"`

cd "$DIRNAME" || exit 1

EXPECTED=`awk '{print $1}' "$HASHBASE"`
ACTUAL=`sha256sum "$BASENAME" | awk '{print $1}'`

[ "$EXPECTED" = "$ACTUAL" ] || exit 1

echo "$MSG_UPDATE"

ESC_DESC=`printf '%s\n' "$DESC" | sed 's/[&|]/\\&/g'`
sed "s|^description=.*|description=$ESC_DESC|" "$BASENAME" > "$BASENAME.tmp"
mv "$BASENAME.tmp" "$BASENAME"

echo "$MSG_REGEN"

sha256sum "$BASENAME" > "$HASHBASE"

echo "$MSG_DONE"

touch "$GATE"
