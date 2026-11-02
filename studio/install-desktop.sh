#!/usr/bin/env bash
# Puts macOS Theme Studio in the app launcher for this user: a launcher entry
# with its name and icon, which the bar, the dock and the app switcher also
# show for its window. Build it first (cargo build --release).
#
#   ./install-desktop.sh                     the app manages ~/.local/share/omarchy-macos-theme
#   ./install-desktop.sh ..                  it manages the theme in this checkout instead
#   ./install-desktop.sh --remove            take the entry and icon away
set -euo pipefail

repo="$(cd "$(dirname "$0")" && pwd)"
data="${XDG_DATA_HOME:-$HOME/.local/share}"
id=omarchy-macos-studio
entry="$data/applications/$id.desktop"
icon="$data/icons/hicolor/scalable/apps/$id.svg"

refresh() {
  update-desktop-database -q "$data/applications" 2>/dev/null || true
  gtk-update-icon-cache -q -t "$data/icons/hicolor" 2>/dev/null || true
}

if [[ ${1:-} == --remove ]]; then
  rm -f "$entry" "$icon"
  refresh
  echo "Removed macOS Theme Studio from the app launcher"
  exit 0
fi

binary="$repo/target/release/$id"
[[ -x $binary ]] || { echo "Build it first: cargo build --release" >&2; exit 1; }

exec_line=$binary
if [[ -n ${1:-} ]]; then
  theme=$(cd "$1" && pwd) || { echo "No folder $1" >&2; exit 1; }
  [[ -f $theme/install.sh ]] || { echo "$theme has no install.sh; is it the theme?" >&2; exit 1; }
  exec_line="env OMARCHY_MACOS_THEME_DIR=$theme $binary"
fi

mkdir -p "$(dirname "$entry")" "$(dirname "$icon")"
cp "$repo/assets/icon-omarchy.svg" "$icon"
cat > "$entry" <<EOF
[Desktop Entry]
Type=Application
Name=macOS Theme Studio
GenericName=Theme Settings
Comment=Install, customize, back up and update the macOS theme for Omarchy
Exec=$exec_line
Icon=$id
StartupWMClass=$id
Categories=Settings;DesktopSettings;
Keywords=macOS;theme;Omarchy;dock;glass;blur;widgets;lock screen;
Terminal=false
EOF
refresh
echo "Added macOS Theme Studio to the app launcher ($entry)"
