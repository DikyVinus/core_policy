#!/system/bin/sh
# SPDX-License-Identifier: Apache-2.0

MODDIR="${0%/*}"

if pidof coreshift ; then
    for pid in $(pidof coreshift); do
        kill "$pid" 
    done
    sleep 1
    for pid in $(pidof coreshift); do
        kill -9 "$pid" 
    done
fi

OLDIFS="$IFS"
IFS=:
for P in $PATH; do
    case "$P" in
        /data/*)
            [ -L "$P/coreshift" ] && rm -f "$P/coreshift"
            [ -L "$P/cli.xml" ] && rm -f "$P/cli.xml"
            ;;
    esac
done
IFS="$OLDIFS"

exit 0
