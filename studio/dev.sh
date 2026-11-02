#!/usr/bin/env bash
# Watch mode: rebuilds and reopens the app whenever a source file is saved.
# It reopens on the page it was on, which the app remembers by itself.
#
#   ./dev.sh                     against ~/.local/share/omarchy-macos-theme
#   ./dev.sh ~/Projects/omarchy-macos-theme   against a checkout of the theme
#
# Needs inotifywait (inotify-tools). Ctrl+C stops it and closes the app.
set -u

cd "$(dirname "$0")" || exit 1
[[ -n ${1:-} ]] && export OMARCHY_MACOS_THEME_DIR=$1
export QMAKE=${QMAKE:-qmake6}
command -v inotifywait >/dev/null || { echo "Needs inotifywait: sudo pacman -S inotify-tools" >&2; exit 1; }

app=""
stop() { [[ -n $app ]] && kill "$app" 2>/dev/null; wait "$app" 2>/dev/null; app=""; }
trap 'stop; exit 0' INT TERM

while true; do
  # A failed build leaves the last good app open, with the errors above it.
  if cargo build 2>&1 | grep -E "^(error|warning)|^\s+-->|Finished"; [[ ${PIPESTATUS[0]} -eq 0 ]]; then
    stop
    ./target/debug/omarchy-macos-studio &
    app=$!
  fi
  inotifywait -qq -r -e close_write,create,delete,move qml src assets build.rs Cargo.toml
  # Editors save in bursts; let them settle.
  sleep 0.3
done
