#!/bin/bash
# macOS theme: after omarchy-update, brings Omarchy's new lock and PAM code
# into the theme's lock screen clone, keeping its macOS LockView.qml. Added by
# omarchy-macos-theme (install.sh --add lock); --remove lock takes it out.
src=${OMARCHY_PATH:-/usr/share/omarchy}/shell/plugins/lock
[[ -d $src ]] || exit 0
for dir in "${XDG_CONFIG_HOME:-$HOME/.config}"/omarchy/plugins/*; do
  [[ -e $dir/.macos-theme ]] && grep -qs '"clonedFrom": "omarchy.lock"' "$dir/manifest.json" || continue
  for f in "$src"/*; do
    case ${f##*/} in manifest.json | LockView.qml) ;; *) cp -r "$f" "$dir/" ;; esac
  done
done
