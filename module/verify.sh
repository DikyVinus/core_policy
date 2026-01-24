#!/system/bin/sh

MODDIR="$(cd "$(dirname "$0")" && pwd)"

find "$MODDIR" -type f -name '*.sha256' -print0 |
while IFS= read -r -d '' sumfile; do
    target="${sumfile%.sha256}"

    [ -f "$target" ] || exit 1

    expected="$(cat "$sumfile")"
    actual="$(sha256sum "$target" | awk '{print $1}')"

    [ "$expected" = "$actual" ] || exit 1
done
