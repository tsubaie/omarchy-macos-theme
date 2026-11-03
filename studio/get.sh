#!/usr/bin/env bash
# Installs macOS Theme Studio from the latest GitHub release, for this user:
# the program in ~/.local/bin and an entry in the app launcher. Run it again
# to update.
#
#   curl -fsSL https://raw.githubusercontent.com/tsubaie/omarchy-macos-theme/main/studio/get.sh | bash
set -euo pipefail

id=omarchy-macos-studio
arch=$(uname -m)
[[ $arch == x86_64 || $arch == aarch64 ]] || { echo "Studio's releases are for x86_64 and aarch64, not $arch; build it from source instead" >&2; exit 1; }
url=${OMARCHY_MACOS_STUDIO_URL:-https://github.com/tsubaie/omarchy-macos-theme/releases/latest/download/$id-$arch.tar.gz}
bin="${XDG_BIN_HOME:-$HOME/.local/bin}/$id"

command -v pacman >/dev/null || { echo "Studio is built for Omarchy (Arch Linux)" >&2; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
echo "Downloading macOS Theme Studio…"
curl -fL --progress-bar -o "$tmp/studio.tar.gz" "$url"
tar -xzf "$tmp/studio.tar.gz" -C "$tmp"

install -Dm755 "$tmp/$id/$id" "$bin"
OMARCHY_MACOS_STUDIO_BIN="$bin" "$tmp/$id/install-desktop.sh"
echo "Installed $bin. Open macOS Theme Studio from the app launcher."
