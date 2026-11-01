#!/usr/bin/env bash
# Opens the release build against the theme checkout on workspace 5, quietly:
# no change of focus or workspace for whoever is working.
#   ./run.sh [page]
cd "$(dirname "$0")" || exit 1
for pid in $(hyprctl clients -j | jq -r '.[] | select(.class=="omarchy-macos-studio") | .pid'); do kill "$pid"; done
OMARCHY_MACOS_THEME_DIR=${OMARCHY_MACOS_THEME_DIR:-$HOME/Projects/omarchy-macos-theme} \
  setsid ./target/release/omarchy-macos-studio ${1:+--page "$1"} >/dev/null 2>&1 &
for _ in $(seq 40); do
  addr=$(hyprctl clients -j | jq -r '.[] | select(.class=="omarchy-macos-studio") | .address' | head -1)
  [[ -n $addr ]] && break
  sleep 0.1
done
[[ -n $addr ]] && hyprctl dispatch "hl.dsp.window.move({ workspace = \"5\", follow = false, window = \"address:$addr\" })" >/dev/null
