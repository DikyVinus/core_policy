#!/system/bin/sh

# SPDX-License-Identifier: Apache-2.0

set -e

MODDIR="${0%/*}"
LOG="$MODDIR/verify.debug.log"
FAILED=0

UID="$(id -u)"

echo "[verify] UID=$UID" >"$LOG"
echo "[verify] MODDIR=$MODDIR" >>"$LOG"

is_install_only() {
    case "${1##*/}" in
        customize.sh|install.sh|uninstall.sh) return 0 ;;
        *) return 1 ;;
    esac
}

SUMFILES=$(ls "$MODDIR"/*.sha256 2>/dev/null)

for sumfile in $SUMFILES; do
    target="${sumfile%.sha256}"
    name="${target##*/}"

    echo "[verify] checking ${sumfile##*/}" >>"$LOG"  

    if [ ! -f "$target" ]; then  
        if is_install_only "$target"; then  
            echo "[verify] skipped install-only artifact: $name" >>"$LOG"  
        else  
            echo "[verify] MISSING target: $target" >>"$LOG"  
            FAILED=1  
        fi  
        continue  
    fi  


    read -r expected _ < "$sumfile"
    
    
    if command -v sha256sum >/dev/null 2>&1; then
        actual_raw=$(sha256sum "$target")
    else
        actual_raw=$(openssl dgst -sha256 "$target" 2>/dev/null | sed 's/.*= //')
    fi
    
    
    actual="${actual_raw%% *}"

    echo "[verify] expected=$expected" >>"$LOG"  
    echo "[verify] actual=$actual" >>"$LOG"  

    if [ "$expected" != "$actual" ]; then  
        echo "[verify] MISMATCH: $name" >>"$LOG"  
        FAILED=1  
    fi
done

if [ "$FAILED" -ne 0 ]; then
    echo "[verify] verification FAILED" >>"$LOG"
    exit 1
fi

echo "[verify] verification OK" >>"$LOG"
