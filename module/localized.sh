#!/system/bin/sh
set -eu

MODDIR="${0%/*}"
LOG="$MODDIR/localized.log"
XML="$MODDIR/log.xml"
FILE="$MODDIR/module.prop"
HASH="$FILE.sha256"

: >"$LOG"
exec >>"$LOG" 2>&1

SYS_LANG="$(getprop persist.sys.locale | cut -d- -f1)"
[ -n "$SYS_LANG" ] || SYS_LANG="$(getprop ro.product.locale | cut -d- -f1)"

case "$SYS_LANG" in
    en|id|zh|ar|ja|es|hi|pt|ru|de)
        LANG_CODE="$SYS_LANG"
        ;;
    *)
        LANG_CODE="en"
        ;;
esac

xml_get() {
    id="$1"
    lang="$2"
    fallback="$3"

    [ -f "$XML" ] || { echo "$fallback"; return; }

    awk -v id="$id" -v lang="$lang" '
        $0 ~ "<section id=\""id"\">" { f=1; next }
        f && /<\/section>/ { exit }
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
        }
    ' "$XML" | head -n1 | sed 's/&lt;/</g; s/&gt;/>/g; s/&amp;/\&/g' | {
        read -r line || true
        echo "${line:-$fallback}"
    }
}

MSG_VERIFY="$(xml_get verify_hash "$LANG_CODE" "[*] verifying sha256")"
MSG_UPDATE="$(xml_get update_desc "$LANG_CODE" "[*] updating description")"
MSG_REGEN="$(xml_get regen_hash "$LANG_CODE" "[*] regenerating sha256")"
MSG_DONE="$(xml_get done "$LANG_CODE" "[✓] done")"
DESC="$(xml_get mod_description "$LANG_CODE" "")"

echo "$MSG_VERIFY"
(
    cd "$(dirname "$FILE")"
    sha256sum -c "$(basename "$HASH")"
)

echo "$MSG_UPDATE"
ESC_DESC="$(printf '%s\n' "$DESC" | sed 's/[&|]/\\&/g')"
sed -i "s|^description=.*|description=$ESC_DESC|" "$FILE"


echo "$MSG_REGEN"
(
    cd "$(dirname "$FILE")"
    sha256sum "$(basename "$FILE")" >"$(basename "$HASH")"
)

echo "$MSG_DONE"
