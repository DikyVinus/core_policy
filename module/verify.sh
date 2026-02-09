#!/system/bin/sh
set -e

MODDIR="${0%/*}"
LOG="$MODDIR/verify.debug.log"
FAILED=0

UID="$(id -u)"

echo "[verify] UID=$UID" >"$LOG"
echo "[verify] MODDIR=$MODDIR" >>"$LOG"

is_install_only() {
    case "$(basename "$1")" in
        customize.sh|install.sh|uninstall.sh) return 0 ;;
        *) return 1 ;;
    esac
}

set -- "$MODDIR"/*.sha256
[ "$1" = "$MODDIR/*.sha256" ] && set --

for sumfile; do
    target="${sumfile%.sha256}"
    name="$(basename "$target")"

    echo "[verify] checking $(basename "$sumfile")" >>"$LOG"

    if [ ! -f "$target" ]; then
        if is_install_only "$target"; then
            echo "[verify] skipped install-only artifact: $name" >>"$LOG"
        else
            echo "[verify] MISSING target: $target" >>"$LOG"
            FAILED=1
        fi
        continue
    fi

    expected="$(cat "$sumfile")"
    actual="$(sha256sum "$target" | awk '{print $1}')"

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
