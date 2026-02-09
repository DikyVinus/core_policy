#!/system/bin/sh

MODDIR="${0%/*}"
BIN="$MODDIR/system/bin"
CORESHIFT_BIN="$BIN/coreshift"

command -v ui_print >/dev/null 2>&1 || ui_print() { echo "$@"; }
ui_print "[CorePolicy] Uninstall: stopping daemon and cleaning symlinks"

# Kill running coreshift daemons
if pidof coreshift ; then
    for pid in $(pidof coreshift ); do
        kill "$pid" 2>/dev/null
    done
    sleep 1
    for pid in $(pidof coreshift ); do
        kill -9 "$pid" 
    done
    ui_print "[CorePolicy] coreshift daemon stopped"
fi

# Remove only symlinks created during install
for P in ${PATH//:/ }; do
    case "$P" in
        /data/*)
            [ -L "$P/coreshift" ] && rm -f "$P/core*" && ui_print "[CorePolicy] removed $P/coreshift"
            [ -L "$P/cli.xml" ] && rm -f "$P/cli.xml" && ui_print "[CorePolicy] removed $P/cli.xml"
            ;;
    esac
done

ui_print "[CorePolicy] Uninstall complete"
