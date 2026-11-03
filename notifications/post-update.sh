#!/bin/bash
# macOS theme: after omarchy-update, brings Omarchy's new notifications code
# into the theme's notifications clone, keeping its macOS Toast.qml. Added by
# omarchy-macos-theme (install.sh --add notifications); --remove notifications
# takes it out.
src=${OMARCHY_PATH:-/usr/share/omarchy}/shell/plugins/notifications
[[ -d $src ]] || exit 0
for dir in "${XDG_CONFIG_HOME:-$HOME/.config}"/omarchy/plugins/*; do
  [[ -e $dir/.macos-theme ]] && grep -qs '"clonedFrom": "omarchy.notifications"' "$dir/manifest.json" || continue
  for f in "$src"/*; do
    case ${f##*/} in manifest.json | Toast.qml) ;; *) cp -r "$f" "$dir/" ;; esac
  done
done
