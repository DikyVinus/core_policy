#!/system/bin/sh
# CorePolicy – verify.sh
# Runtime integrity verification (UID-based, tolerant)

UID="$(id -u)"

if [ "$UID" -eq 0 ]; then
    MODDIR="/data/adb/modules/core_policy"
else
    MODDIR="${AXERONDIR}/plugins/core_policy"
fi

LOG="$MODDIR/verify.debug.log"

echo "[verify] UID=$UID" > "$LOG"
echo "[verify] MODDIR=$MODDIR" >> "$LOG"

# install-only artifacts that may not exist at runtime
is_install_only() {
    case "$(basename "$1")" in
        customize.sh|install.sh|uninstall.sh)
            return 0
            ;;
    esac
    return 1
}

FAILED=0

find "$MODDIR" -type f -name '*.sha256' -print0 |
while IFS= read -r -d '' sumfile; do
    target="${sumfile%.sha256}"
    name="$(basename "$target")"

    echo "[verify] checking $(basename "$sumfile")" >> "$LOG"

    if [ ! -f "$target" ]; then
        if is_install_only "$target"; then
            echo "[verify] skipped install-only artifact: $name" >> "$LOG"
            continue
        else
            echo "[verify] MISSING target: $target" >> "$LOG"
            FAILED=1
            continue
        fi
    fi

    expected="$(cat "$sumfile")"
    actual="$(sha256sum "$target" | awk '{print $1}')"

    echo "[verify] expected=$expected" >> "$LOG"
    echo "[verify] actual=$actual" >> "$LOG"

    if [ "$expected" != "$actual" ]; then
        echo "[verify] MISMATCH: $name" >> "$LOG"
        FAILED=1
    fi
done

if [ "$FAILED" -ne 0 ]; then
    echo "[verify] verification FAILED" >> "$LOG"
    exit 1
fi

echo "[verify] verification OK" >> "$LOG"
exit 0
