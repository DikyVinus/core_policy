#!/system/bin/sh
# SPDX-License-Identifier: Apache-2.0

MODDIR="${0%/*}"
LOG="$MODDIR/verify.debug.log"
FAILED=0

echo "[verify] UID=`id -u`" >"$LOG"
echo "[verify] MODDIR=$MODDIR" >>"$LOG"

is_install_only() {
    case "${1##*/}" in
        customize.sh|install.sh|uninstall.sh) return 0 ;;
    esac
    return 1
}

has_sha=0
which sha256sum >/dev/null 2>&1 && has_sha=1

for sumfile in `ls "$MODDIR"/*.sha256 2>/dev/null`; do
    target="${sumfile%.sha256}"
    name="${target##*/}"

    echo "[verify] checking ${sumfile##*/}" >>"$LOG"

    if is_install_only "$target"; then
    if [ ! -f "$target" ]; then
        echo "[verify] install-only artifact not present (ok): $name" >>"$LOG"
        continue
    fi
fi

if [ ! -f "$target" ]; then
    echo "[verify] MISSING target: $target" >>"$LOG"
    FAILED=1
    continue
fi

    if [ "$has_sha" -eq 1 ]; then
        read expected _ < "$sumfile"
        actual=`sha256sum "$target"`
        actual="${actual%% *}"

        echo "[verify] expected=$expected" >>"$LOG"
        echo "[verify] actual=$actual" >>"$LOG"

        [ "$expected" = "$actual" ] || {
            echo "[verify] MISMATCH: $name" >>"$LOG"
            FAILED=1
        }
    else
        sum_mtime=`ls -ln "$sumfile" | awk '{print $6,$7,$8}'`
        tgt_mtime=`ls -ln "$target" | awk '{print $6,$7,$8}'`

        echo "[verify] sum_mtime=$sum_mtime" >>"$LOG"
        echo "[verify] tgt_mtime=$tgt_mtime" >>"$LOG"

        [ "$sum_mtime" = "$tgt_mtime" ] || {
            echo "[verify] MTIME MISMATCH: $name" >>"$LOG"
            FAILED=1
        }
    fi
done

if [ "$FAILED" -ne 0 ]; then
    echo "[verify] verification FAILED" >>"$LOG"
    exit 1
fi

echo "[verify] verification OK" >>"$LOG"
