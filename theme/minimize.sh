#!/usr/bin/env bash
# macOS-style minimize for the yellow title-bar button: shrink and fade the
# window toward the dock, then hand it to Omarchy's own minimize so the dock
# brings it back as usual.
set -u

addr=${1:?usage: minimize.sh <window address>}
d() { hyprctl dispatch "$1" >/dev/null; }

read -r ws x y w h mon < <(hyprctl clients -j | jq -r --arg a "$addr" \
  '.[] | select(.address == $a) | "\(.workspace.id) \(.at[0]) \(.at[1]) \(.size[0]) \(.size[1]) \(.monitor)"')
[[ -n ${ws:-} ]] || exit 1

# Omarchy minimizes only on floating workspaces; elsewhere do nothing, as it does.
[[ $(omarchy-hyprland-workspace-layout-current "$ws") == floating ]] || exit 0

read -r mx my mw mh < <(hyprctl monitors -j | jq -r --argjson m "$mon" \
  '.[] | select(.id == $m) | "\(.x) \(.y) \(.width) \(.height)"')
opacity=$(hyprctl getprop "address:$addr" opacity 2>/dev/null) || opacity=1

# Shrink to a sixth, centered over the dock, while fading out; Hyprland's own
# window and fade animations make the motion.
tw=$((w / 6)) th=$((h / 6))
d "hl.dsp.window.resize({ x = $tw, y = $th, window = \"address:$addr\" })"
d "hl.dsp.window.move({ x = $((mx + mw / 2 - tw / 2)), y = $((my + mh - th - 40)), window = \"address:$addr\" })"
d "hl.dsp.window.set_prop({ prop = \"opacity\", value = \"0\", window = \"address:$addr\" })"
sleep 0.3

omarchy-hyprland-window-minimize "$addr"

# Put it back as it was while it is hidden, so it returns from the dock intact.
d "hl.dsp.window.resize({ x = $w, y = $h, window = \"address:$addr\" })"
d "hl.dsp.window.move({ x = $x, y = $y, window = \"address:$addr\" })"
d "hl.dsp.window.set_prop({ prop = \"opacity\", value = \"$opacity\", window = \"address:$addr\" })"
