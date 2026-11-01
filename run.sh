#!/usr/bin/env bash
# Opens the release build against the theme checkout on workspace 5, quietly:
# no change of focus or workspace for whoever is working.
#   ./run.sh [page]
# It opens there rather than being moved there: a window moved to a hidden
# workspace before its first frame can show a stale, wrongly sized one.
cd "$(dirname "$0")" || exit 1
for pid in $(hyprctl clients -j | jq -r '.[] | select(.class=="omarchy-macos-studio") | .pid'); do kill "$pid"; done
# The old window is gone before the new one comes.
for _ in $(seq 40); do
  [[ -z $(hyprctl clients -j | jq -r '.[] | select(.class=="omarchy-macos-studio") | .pid') ]] && break
  sleep 0.1
done
theme=${OMARCHY_MACOS_THEME_DIR:-$HOME/Projects/omarchy-macos-theme}
cmd="[workspace 5 silent] env OMARCHY_MACOS_THEME_DIR=$(printf %q "$theme") $(printf %q "$PWD/target/release/omarchy-macos-studio")${1:+ --page $(printf %q "$1")}"
hyprctl dispatch "hl.dsp.exec_cmd($(jq -Rn --arg c "$cmd" '$c'))" >/dev/null
