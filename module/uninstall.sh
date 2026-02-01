#!/system/bin/sh
exec 2>/dev/null

APP_PKG="com.coreshift.policy"
APP_SERVICE="$APP_PKG/.TopAppService"

ENABLED="$(cmd settings get secure enabled_accessibility_services)"

case "$ENABLED" in
    *"$APP_SERVICE"*)
        NEW="$(echo "$ENABLED" | sed "s#:$APP_SERVICE##; s#$APP_SERVICE:##; s#$APP_SERVICE##")"
        cmd settings put secure enabled_accessibility_services "$NEW"
        ;;
esac

[ "$ENABLED" = "$APP_SERVICE" ] && cmd settings put secure accessibility_enabled 0

cmd package uninstall "$APP_PKG"

BB="$(command -v resetprop)" || exit 0
BB="$(readlink -f "$BB" || echo "$BB")"
BINDIR="$(dirname "$BB")"

for name in core_policy_discovery core_policy_exe core_policy_demote; do
    target="$BINDIR/$name"
    if [ -L "$target" ]; then
        link="$(readlink "$target")"
        case "$link" in
            */core_policy/*)
                rm -f "$target"
                ;;
        esac
    fi
done
