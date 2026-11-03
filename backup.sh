# Snapshots, export and import for install.sh, which sources this file.
#
# A snapshot is a copy of what the theme changes, taken before every change so
# any of them can be undone on this computer: shell.json, looknfeel.lua,
# gtk.css, the theme folder, and the plugins the theme manages (its own, and
# its clones of Omarchy's menu and lock). Other plugins are left out, so a
# restore never touches them; the three files come back whole, though.
#
# An export holds your choices instead of files (which pieces, the settings,
# the dock and widget setup, your own wallpapers), and an import re-applies
# them with the installer it runs in, so it fits a new install or a newer
# version of Omarchy and the theme.

SNAPSHOTS="$BACKUP_DIR/snapshots"
# Snapshots kept besides the first one, which is kept for good.
SNAPSHOT_KEEP=10
SNAPSHOT_FILES="omarchy/shell.json hypr/looknfeel.lua gtk-4.0/gtk.css"
SNAPSHOT_ID_PATTERN='^[0-9]{8}-[0-9]{6}(-[0-9]+)?$'
# Snapshots in the order they were taken: by the second, then by the number a
# second one in the same second gets (-2, -3, …), as a number, not as text.
SNAPSHOT_ORDER='def taken: .id | capture("^(?<at>[0-9]{8}-[0-9]{6})(-(?<n>[0-9]+))?$") | [.at, ((.n // "1") | tonumber)];'
EXPORT_FORMAT=1

# The plugin folders the theme manages, relative to $CONFIG: its own, and its
# clones of Omarchy's menu and lock (never clones of yours). Not its workspaces
# clone: snapshots made before held none, so restoring one would take it off
# the bar it is still on; --add menubar makes it afresh anyway.
managed_plugins() {
  local dir
  for dir in "$PLUGINS_DIR"/macos-theme.* $(wide_menus) $(macos_locks); do
    [[ -d $dir ]] && echo "omarchy/plugins/$(basename "$dir")"
  done | sort -u
}

# What changes, in a few words, for a snapshot's note.
describe_changes() {
  local parts=() k
  (( ${#add[@]} )) && parts+=("Added ${!add[*]}")
  (( ${#remove[@]} )) && parts+=("Removed ${!remove[*]}")
  for k in "${!settings[@]}"; do parts+=("$k ${settings[$k]}"); done
  [[ -n ${bar_layout:-} ]] && parts+=("Arranged the bar")
  [[ -n ${show_widgets:-} ]] && parts+=("Showed widgets ${show_widgets//,/, }")
  local IFS=';'
  echo "${parts[*]}" | sed 's/;/; /g'
}

# Takes a snapshot with a note, and prints its id.
snapshot_take() {
  local note="$1" id dir paths=() p first=false original=false
  id=$(date +%Y%m%d-%H%M%S)
  local base=$id n=1
  while [[ -d $SNAPSHOTS/$id ]]; do id="$base-$((++n))"; done
  dir="$SNAPSHOTS/$id"
  [[ -n $(ls -A "$SNAPSHOTS" 2>/dev/null) ]] || first=true
  mkdir -p "$dir"

  # The three files by their contents, read through a dotfiles symlink: tar
  # would keep only the link, and a restore would undo nothing.
  local files=() copies="$dir/.files"
  for p in $SNAPSHOT_FILES; do
    [[ -e $CONFIG/$p ]] || continue
    mkdir -p "$copies/$(dirname "$p")" && cp -L "$CONFIG/$p" "$copies/$p" && files+=("$p")
  done
  while read -r p; do [[ -n $p ]] && paths+=("$p"); done < <(managed_plugins)
  [[ -d $THEME_DIR ]] && paths+=("omarchy/themes/macos")

  # The theme's own wallpapers and preview come back from the repo on restore.
  local excludes=(--exclude="omarchy/themes/macos/preview.png")
  for p in "$REPO"/theme/backgrounds/*; do
    excludes+=(--exclude="omarchy/themes/macos/backgrounds/$(basename "$p")")
  done
  # Before the theme there may be nothing yet, which is a valid snapshot too.
  local from=()
  (( ${#files[@]} )) && from+=(-C "$copies" "${files[@]}")
  (( ${#paths[@]} )) && from+=(-C "$CONFIG" "${paths[@]}")
  if (( ${#from[@]} )); then
    tar "${excludes[@]}" -czf "$dir/files.tar.gz" "${from[@]}"
    rm -rf "${copies:?}"
  else
    tar -czf "$dir/files.tar.gz" -T /dev/null
  fi

  if $first; then
    original=true
    for p in $FEATURES; do installed "$p" && original=false; done
  fi
  # The theme's background too, which lives outside these files.
  jq -n --arg id "$id" --arg created "$(date -Iseconds)" --arg note "$note" \
    --arg theme "$(omarchy theme current 2>/dev/null)" --arg background "$(background_now)" \
    --argjson pinned "$first" --argjson original "$original" \
    '{id: $id, created: $created, note: $note, theme: $theme, background: $background, pinned: $pinned, original: $original}' \
    > "$dir/meta.json"
  snapshot_prune
  echo "$id"
}

# Keeps the first snapshot and the newest $SNAPSHOT_KEEP others.
snapshot_prune() {
  local old
  jq -rs --argjson keep "$SNAPSHOT_KEEP" \
    "$SNAPSHOT_ORDER"' [.[] | select(.pinned | not)] | sort_by(taken) | reverse | .[$keep:][] | .id' \
    "$SNAPSHOTS"/*/meta.json 2>/dev/null | while read -r old; do
    [[ $old =~ $SNAPSHOT_ID_PATTERN ]] && rm -rf "${SNAPSHOTS:?}/$old"
  done
}

snapshot_list_json() {
  if compgen -G "$SNAPSHOTS/*/meta.json" >/dev/null; then
    jq -s "$SNAPSHOT_ORDER"' sort_by(taken) | reverse' "$SNAPSHOTS"/*/meta.json
  else
    echo "[]"
  fi
}

snapshot_list_text() {
  snapshot_list_json | jq -r '.[] | "\(.id)  \(.created[0:16] | sub("T"; " "))  \(if .original then "Before macOS theme" else .note end)\(if .pinned then "  (kept)" else "" end)"'
}

# Puts a snapshot's files in place of the theme's, all or nothing: they are
# unpacked beside them first, so a damaged archive changes nothing.
snapshot_unpack() {
  local stage p moved=true
  # A restore killed half-way leaves its folder; the next one clears it.
  rm -rf "${CONFIG:?}"/.macos-theme-restore.*
  stage=$(mktemp -d "$CONFIG/.macos-theme-restore.XXXXXX") || return 1
  tar -C "$stage" --no-same-owner -xzf "$1" 2>/dev/null || { rm -rf "${stage:?}"; return 1; }

  while read -r p; do [[ -n $p ]] && rm -rf "${CONFIG:?}/$p"; done < <(managed_plugins)
  rm -rf "${THEME_DIR:?}"
  # Same filesystem, so each move is a rename. Globbed, so names may hold spaces.
  # Written into, not replaced: a dotfiles symlink stays one, and its file
  # gets the contents back. One the snapshot doesn't hold wasn't there then.
  # A snapshot from before that held the link itself: put the link back, and
  # never write through it, which could be onto the very file it points at.
  for p in $SNAPSHOT_FILES; do
    if [[ -L $stage/$p ]]; then
      rm -f "${CONFIG:?}/$p"
      unpack_move "$stage" "$stage/$p" || moved=false
    elif [[ -f $stage/$p ]]; then
      { mkdir -p "$(dirname "$CONFIG/$p")" && cat "$stage/$p" >"$CONFIG/$p"; } || moved=false
    else
      rm -f "${CONFIG:?}/$p"
    fi
  done
  for p in "$stage"/omarchy/plugins/* "$stage/omarchy/themes/macos"; do unpack_move "$stage" "$p" || moved=false; done
  rm -rf "${stage:?}"
  # The theme's own files, left out of snapshots.
  [[ -d $THEME_DIR ]] && cp -rn "$REPO/theme/." "$THEME_DIR/"
  $moved
}
# unpack_move <stage> <path in it>: moves it to the same place under $CONFIG.
unpack_move() {
  [[ -e $2 || -L $2 ]] || return 0
  local to="$CONFIG/${2#"$1"/}"
  # Still there after the theme's own were cleared, so not the theme's: a
  # clone of yours that an older snapshot holds too. Yours stays as it is.
  [[ -e $to || -L $to ]] && return 0
  mkdir -p "$(dirname "$to")" && mv "$2" "$to"
}

# Puts a snapshot back: first a snapshot of now, so the restore can be undone,
# then the files, then the Omarchy theme that was current, reloaded once.
snapshot_restore() {
  local id="$1" dir="$SNAPSHOTS/$1" p theme
  [[ $id =~ $SNAPSHOT_ID_PATTERN && -f $dir/files.tar.gz ]] ||
    { echo "No backup called $id (see: ./install.sh --backups)" >&2; exit 1; }
  tar -tzf "$dir/files.tar.gz" >/dev/null 2>&1 ||
    { echo "The backup $id is damaged and can't be restored; nothing was changed" >&2; exit 1; }
  theme=$(jq -r '.theme // ""' "$dir/meta.json")
  local undo
  undo=$(snapshot_take "Before restoring $(jq -r '.created[0:16] | sub("T"; " ")' "$dir/meta.json")")

  if ! snapshot_unpack "$dir/files.tar.gz"; then
    if snapshot_unpack "$SNAPSHOTS/$undo/files.tar.gz"; then
      echo "Couldn't restore the backup $id; your files were put back as they were" >&2
    else
      echo "Couldn't restore the backup $id; put your files back with: ./install.sh --restore $undo" >&2
    fi
    exit 1
  fi

  # Kept outside snapshots, so put in step with what came back: the lock's
  # update hook goes with the theme's lock, and before the theme there were
  # no MacTahoe icons of its own.
  if [[ -n $(macos_locks) ]]; then
    mkdir -p "$(dirname "$LOCK_HOOK")" && cp "$REPO/lock/post-update.sh" "$LOCK_HOOK"
  else
    rm -f "$LOCK_HOOK"
  fi
  if jq -e '.original == true' "$dir/meta.json" >/dev/null && installed icons; then remove_icons; fi

  if [[ -n $theme && $theme != "$(omarchy theme current 2>/dev/null)" ]]; then
    omarchy theme set "$theme"
  else
    if active; then refresh; else
      hyprctl reload >/dev/null 2>&1 || true
      omarchy restart shell >/dev/null 2>&1 || true
    fi
  fi
  # The theme's background as it was, if the snapshot noted one that's still there.
  local bg
  bg=$(jq -r '.background // ""' "$dir/meta.json")
  [[ -f $bg && $bg != "$(background_now)" ]] && show_background "$bg"
  say "Restored the backup from $(jq -r '.created[0:16] | sub("T"; " ")' "$dir/meta.json") (undo with: ./install.sh --restore $undo)"
}

# The theme's own wallpaper names, to tell them from yours.
repo_wallpaper() { [[ -e $REPO/theme/backgrounds/$1 ]]; }

# Writes your choices to one file: a directory gets a dated name inside it.
export_profile() {
  local target="$1" tmp f
  [[ -d $target ]] && target="$target/macos-theme-$(date +%Y-%m-%d).tar.gz"
  tmp=$(mktemp -d)
  mkdir -p "$tmp/backgrounds"

  local pieces=()
  for f in $FEATURES; do installed "$f" && pieces+=("$f"); done
  local shell="{}"
  [[ -s $SHELL_JSON ]] && shell=$(jq '{dock: (.dock // null), widgets: (.widgets // null)}' "$SHELL_JSON")
  local set_json="{}"
  if installed theme; then
    for f in $LOOK_SETTINGS; do set_json=$(jq --arg k "$f" --argjson v "$(look_get "$f")" '.[$k] = $v' <<<"$set_json"); done
  fi
  set_json=$(jq --argjson v "$(magnification)" --arg c "$(clock_position)" \
    --arg vh "$(hud_position volume)" --arg dh "$(hud_position dictation)" \
    '.magnification = $v | .clock = $c | .["volume-hud"] = $vh | .["dictation-hud"] = $dh' <<<"$set_json")

  jq -n --argjson format "$EXPORT_FORMAT" --arg created "$(date -Iseconds)" \
    --arg version "$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null)" \
    --argjson pieces "$(printf '%s\n' "${pieces[@]}" | jq -R . | jq -s 'map(select(. != ""))')" \
    --argjson settings "$set_json" --argjson shell "$shell" \
    '{format: $format, created: $created, version: $version, pieces: $pieces, settings: $settings, shell: $shell}' \
    > "$tmp/profile.json"

  if [[ -d $THEME_DIR/backgrounds ]]; then
    for f in "$THEME_DIR"/backgrounds/*; do
      [[ -f $f ]] && ! repo_wallpaper "$(basename "$f")" && cp "$f" "$tmp/backgrounds/"
    done
  fi
  tar -C "$tmp" -czf "$target" profile.json backgrounds
  rm -rf "${tmp:?}"
  say "Exported your macOS theme setup to $target"
}

# Re-applies an export: the pieces and settings through this installer, then
# the dock and widget setup and your wallpapers. Only a profile and images are
# taken from the file; anything else in it is refused.
import_profile() {
  local file="$1" tmp entry
  [[ -f $file ]] || { echo "No file $file" >&2; exit 1; }
  while read -r entry; do
    [[ $entry =~ ^(\./)?(profile\.json|backgrounds/?|backgrounds/[A-Za-z0-9._\ -]+\.(jpg|jpeg|png|webp))$ ]] ||
      { echo "Not a macOS theme export (unexpected $entry)" >&2; exit 1; }
  done < <(tar -tzf "$file" 2>/dev/null || echo "?")
  # Plain files and folders only: a link would let it copy any file of yours.
  [[ -z $(tar -tvzf "$file" | cut -c1 | grep -v '[-d]') ]] ||
    { echo "Not a macOS theme export (it holds links)" >&2; exit 1; }
  tmp=$(mktemp -d)
  tar -C "$tmp" --no-same-owner --no-same-permissions -xzf "$file"
  local profile="$tmp/profile.json"
  [[ $(jq -r '.format // 0' "$profile" 2>/dev/null) == "$EXPORT_FORMAT" ]] ||
    { rm -rf "${tmp:?}"; echo "Not a macOS theme export this version can read" >&2; exit 1; }

  snapshot_take "Before importing $(basename "$file")" >/dev/null

  local args=() f want_pieces
  want_pieces=" $(jq -r '.pieces[]? | strings' "$profile" | tr '\n' ' ') "
  for f in $(jq -r '.pieces[]? | strings' "$profile"); do
    [[ " $FEATURES " == *" $f "* ]] || { echo "    Skipped $f, which this version doesn't have" >&2; continue; }
    installed "$f" || args+=(--add "$f")
  done
  for f in $FEATURES; do
    [[ $want_pieces == *" $f "* ]] && continue
    installed "$f" || continue
    # The current theme can't be removed; it stays.
    [[ $f == theme ]] && active && continue
    args+=(--remove "$f")
  done
  for f in $LOOK_SETTINGS magnification; do
    local v
    v=$(jq -r --arg k "$f" '.settings[$k] | numbers' "$profile")
    # An export from a version that let glass go lower.
    [[ $f == glass && -n $v ]] && v=$(glass_floor "$v")
    [[ -n $v ]] && args+=(--set "$f=$v")
  done
  local clock
  clock=$(jq -r '.settings.clock | strings' "$profile")
  [[ $clock =~ ^(left|center|right)$ ]] && args+=(--set "clock=$clock")
  local hud
  for f in volume-hud dictation-hud; do
    hud=$(jq -r --arg k "$f" '.settings[$k] | strings' "$profile")
    [[ $hud =~ ^(bottom|top)$ ]] && args+=(--set "$f=$hud")
  done
  # A piece that fails still lets the dock, widgets and wallpapers come in;
  # the import fails at the end, with what install.sh said about it.
  local failed=0
  if (( ${#args[@]} )); then
    MACOS_THEME_NO_SNAPSHOT=1 bash "$REPO/install.sh" "${args[@]}" || failed=1
  fi

  # The dock's pinned apps and the widgets' place and layout.
  local key
  for key in dock widgets; do
    [[ $(jq -r --arg k "$key" '.shell[$k] | type' "$profile") == object ]] || continue
    shell_write --arg k "$key" --slurpfile p "$profile" '.[$k] = (.[$k] // {}) + $p[0].shell[$k]'
  done

  if [[ -d $THEME_DIR ]]; then
    mkdir -p "$THEME_DIR/backgrounds"
    for f in "$tmp"/backgrounds/*; do [[ -f $f ]] && cp -n "$f" "$THEME_DIR/backgrounds/"; done
  fi
  rm -rf "${tmp:?}"
  (( ! failed )) || { echo "Imported $(basename "$file"), but not every piece went in (see above)" >&2; exit 1; }
  say "Imported $(basename "$file")"
}
