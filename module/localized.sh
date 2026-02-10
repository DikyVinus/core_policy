#!/system/bin/sh
set -euo pipefail

MODDIR="${0%/*}"
XML="$MODDIR/log.xml"
FILE="$MODDIR/module.prop"
HASH="$FILE.sha256"
exec >$MODDIR/localized.log 2>&1
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

LANG_CODE="${1:-${LANG:-en}}"
LANG_CODE="${LANG_CODE%%_*}"
[ "${#LANG_CODE}" -ne 2 ] && LANG_CODE="en"

MSG_VERIFY="$(xml_get verify_hash "$LANG_CODE" "[*] verifying sha256")"
MSG_UPDATE="$(xml_get update_desc "$LANG_CODE" "[*] updating description")"
MSG_REGEN="$(xml_get regen_hash "$LANG_CODE" "[*] regenerating sha256")"
MSG_DONE="$(xml_get done "$LANG_CODE" "[✓] done")"

DESC="$(xml_get mod_description "$LANG_CODE" "")"

echo "$MSG_VERIFY"
sha256sum -c "$HASH"

echo "$MSG_UPDATE"
sed -i "s|^description=.*|description=$DESC|" "$FILE"

echo "$MSG_REGEN"
sha256sum "$FILE" > "$HASH"

echo "$MSG_DONE"
