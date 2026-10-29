#!/usr/bin/env bash
# macOS-style minimize for the yellow title-bar button: the macOS dock plugin
# pours the window into its icon with the genie, then minimizes it the way
# Omarchy does, so the dock brings it back (out of the icon again). Without the
# plugin, it is Omarchy's plain minimize.
set -u

addr=${1:?usage: minimize.sh <window address>}

read -r ws x y w h mon < <(hyprctl clients -j | jq -r --arg a "$addr" \
  '.[] | select(.address == $a) | "\(.workspace.id) \(.at[0]) \(.at[1]) \(.size[0]) \(.size[1]) \(.monitor)"')
[[ -n ${ws:-} ]] || exit 1

# Omarchy minimizes only on floating workspaces; elsewhere do nothing, as it does.
[[ $(omarchy-hyprland-workspace-layout-current "$ws") == floating ]] || exit 0

if [[ -f ${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/macos-theme.dock/Genie.qml ]]; then
  monitor=$(hyprctl monitors -j | jq -r --argjson m "$mon" '.[] | select(.id == $m) | .name')
  # The title bar sits above the window's own area; the genie takes both.
  bar=$(hyprctl -j getoption plugin:hyprbars:bar_height 2>/dev/null | jq -r '.int // 0')
  omarchy-shell omarchy.dock minimize "$addr" "$x" "$((y - bar))" "$w" "$((h + bar))" "$monitor" >/dev/null 2>&1 && exit 0
fi

omarchy-hyprland-window-minimize "$addr"
