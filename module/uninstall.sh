for bin in "$DISCOVERY" "$EXE" "$DEMOTE"; do
    name="$(basename "$bin")"
    target="$BINDIR/$name"
    [ -L "$target" ] || ln -s "$bin" "$target"
done
