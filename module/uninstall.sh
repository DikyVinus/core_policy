#!/system/bin/sh
exec 2>/dev/null

BB="$(command -v busybox)" || exit 0
BINDIR="$(dirname "$(readlink -f "$BB" 2>/dev/null || echo "$BB")")"

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
