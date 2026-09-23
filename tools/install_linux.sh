#!/usr/bin/env bash
# Installs Shadow Checkers for the current user:
#   ~/.local/bin/shadow-checkers                (the exported release binary)
#   ~/.local/share/applications/shadow-checkers.desktop
#   ~/.local/share/icons/hicolor/*/apps/shadow-checkers.{png,svg}
# Saves and settings (XDG dirs) are never touched.  --uninstall removes the
# binary, launcher, and icons.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN_SRC="$ROOT/export/linux/shadow-checkers.x86_64"
BINDIR="${HOME}/.local/bin"
PREFIX="${XDG_DATA_HOME:-$HOME/.local/share}"
ICON_NAME="shadow-checkers"
VERSION="$(sed -n 's/^config\/version="\(.*\)"/\1/p' "$ROOT/project.godot")"

if [[ "${1:-}" == "--uninstall" ]]; then
	rm -f "$BINDIR/shadow-checkers"
	rm -f "$PREFIX/applications/shadow-checkers.desktop"
	for size in 16 22 24 32 48 64 128 256 512; do
		rm -f "$PREFIX/icons/hicolor/${size}x${size}/apps/${ICON_NAME}.png"
	done
	rm -f "$PREFIX/icons/hicolor/scalable/apps/${ICON_NAME}.svg"
	echo "Removed Shadow Checkers. Saves in $PREFIX/shadow-checkers were kept."
	exit 0
fi

if [[ ! -x "$BIN_SRC" ]]; then
	echo "Exporting Linux release…"
	"$ROOT/tools/export_linux.sh"
fi

mkdir -p "$BINDIR" "$PREFIX/applications"
# Replace any older launcher script or binary atomically.
install -m 0755 "$BIN_SRC" "$BINDIR/.shadow-checkers.new"
mv -f "$BINDIR/.shadow-checkers.new" "$BINDIR/shadow-checkers"

for size in 16 22 24 32 48 64 128 256 512; do
	src="$ROOT/assets/icons/hicolor/${size}x${size}/apps/${ICON_NAME}.png"
	if [[ -f "$src" ]]; then
		mkdir -p "$PREFIX/icons/hicolor/${size}x${size}/apps"
		install -m 0644 "$src" "$PREFIX/icons/hicolor/${size}x${size}/apps/${ICON_NAME}.png"
	fi
done
mkdir -p "$PREFIX/icons/hicolor/scalable/apps"
install -m 0644 "$ROOT/icon.svg" "$PREFIX/icons/hicolor/scalable/apps/${ICON_NAME}.svg"

cat > "$PREFIX/applications/shadow-checkers.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Version=1.0
Name=Shadow Checkers
GenericName=Draughts
Comment=3D checkers for Linux — English, Russian, and Brazilian rules
Exec=${BINDIR}/shadow-checkers
TryExec=${BINDIR}/shadow-checkers
Icon=${ICON_NAME}
Terminal=false
Categories=Game;BoardGame;
Keywords=checkers;draughts;shashki;board;3d;shadowfetch;
StartupNotify=true
StartupWMClass=Shadow Checkers
X-AppVersion=${VERSION}
DESKTOP
sed -e "s#^Exec=.*#Exec=shadow-checkers#" -e "s#^TryExec=.*#TryExec=shadow-checkers#" \
	"$PREFIX/applications/shadow-checkers.desktop" > "$ROOT/packaging/shadow-checkers.desktop"

if command -v desktop-file-validate >/dev/null; then
	desktop-file-validate "$PREFIX/applications/shadow-checkers.desktop" || true
fi
update-desktop-database "$PREFIX/applications" >/dev/null 2>&1 || true
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
	gtk-update-icon-cache -f -t "$PREFIX/icons/hicolor" >/dev/null 2>&1 || true
fi
echo "Installed Shadow Checkers ${VERSION}"
echo "  binary:   $BINDIR/shadow-checkers"
echo "  launcher: $PREFIX/applications/shadow-checkers.desktop"
