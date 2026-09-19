#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOME_DIR="${HOME}"
ICON_SRC="$ROOT/icon.svg"
if [[ ! -f "$ICON_SRC" ]]; then
	ICON_SRC="$ROOT/assets/icons/shadow-checkers.svg"
fi
HICOLOR="$HOME_DIR/.local/share/icons/hicolor"
APP_DIR="$HOME_DIR/.local/share/applications"
BIN_DIR="$HOME_DIR/.local/bin"
SIZES=(16 22 24 32 48 64 128 256 512)

mkdir -p "$HICOLOR/scalable/apps" "$APP_DIR" "$BIN_DIR" "$ROOT/assets/icons/hicolor/scalable/apps"

cp "$ICON_SRC" "$HICOLOR/scalable/apps/shadow-checkers.svg"
cp "$ICON_SRC" "$ROOT/assets/icons/shadow-checkers.svg"
cp "$ICON_SRC" "$ROOT/assets/icons/hicolor/scalable/apps/shadow-checkers.svg"

for sz in "${SIZES[@]}"; do
	mkdir -p "$HICOLOR/${sz}x${sz}/apps" "$ROOT/assets/icons/hicolor/${sz}x${sz}/apps"
	rsvg-convert -w "$sz" -h "$sz" "$ICON_SRC" -o "$HICOLOR/${sz}x${sz}/apps/shadow-checkers.png"
	cp "$HICOLOR/${sz}x${sz}/apps/shadow-checkers.png" "$ROOT/assets/icons/hicolor/${sz}x${sz}/apps/shadow-checkers.png"
done
cp "$HICOLOR/512x512/apps/shadow-checkers.png" "$ROOT/assets/icons/shadow-checkers.png"

cat > "$BIN_DIR/shadow-checkers" <<EOF
#!/usr/bin/env bash
set -euo pipefail
ROOT="\${SHADOW_CHECKERS_ROOT:-$ROOT}"
BIN="\$ROOT/export/linux/shadow-checkers.x86_64"
GODOT="\${GODOT:-\$HOME/.local/bin/godot}"
if [[ -x "\$BIN" ]]; then
	exec "\$BIN" "\$@"
fi
if [[ -x "\$GODOT" ]]; then
	exec "\$GODOT" --path "\$ROOT" "\$@"
fi
echo "Shadow Checkers: no exported binary or Godot editor found." >&2
exit 1
EOF
chmod +x "$BIN_DIR/shadow-checkers"

cat > "$APP_DIR/shadow-checkers.desktop" <<EOF
[Desktop Entry]
Type=Application
Version=1.0
Name=Shadow Checkers
GenericName=Checkers
Comment=Premium 3D English/American checkers for Linux
Exec=$BIN_DIR/shadow-checkers
TryExec=$BIN_DIR/shadow-checkers
Icon=shadow-checkers
Terminal=false
Categories=Game;BoardGame;
Keywords=checkers;draughts;board;3d;shadow;
StartupNotify=true
StartupWMClass=Shadow Checkers
EOF
cp "$APP_DIR/shadow-checkers.desktop" "$ROOT/packaging/shadow-checkers.desktop"

desktop-file-validate "$APP_DIR/shadow-checkers.desktop"
update-desktop-database "$APP_DIR" >/dev/null 2>&1 || true
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
	gtk-update-icon-cache -f "$HICOLOR" >/dev/null 2>&1 || true
fi

echo "Installed Shadow Checkers launcher:"
echo "  $BIN_DIR/shadow-checkers"
echo "  $APP_DIR/shadow-checkers.desktop"
echo "  $HICOLOR/scalable/apps/shadow-checkers.svg"
