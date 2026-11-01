# Snapshots, export and import for install.sh, which sources this file.
#
# A snapshot is a copy of what the theme changes, taken before every change so
# any of them can be undone on this computer: shell.json, looknfeel.lua,
# gtk.css, the theme folder, and the plugins the theme manages (its own, and
# its clones of Omarchy's menu and lock). Other plugins are left out, so
# restoring never rolls back something the theme didn't touch.
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
EXPORT_FORMAT=1

# The plugin folders the theme manages, relative to $CONFIG.
managed_plugins() {
  local dir
  for dir in "$PLUGINS_DIR"/macos-theme.* "$PLUGINS_DIR"/*; do
    [[ -d $dir ]] || continue
    if [[ $(basename "$dir") == macos-theme.* ]] ||
      grep -qsE '"clonedFrom": "omarchy\.(menu|lock)"' "$dir/manifest.json"; then
      echo "omarchy/plugins/$(basename "$dir")"
    fi
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
  [[ -d $SNAPSHOTS/$id ]] && id="$id-$$"
  dir="$SNAPSHOTS/$id"
  [[ -n $(ls -A "$SNAPSHOTS" 2>/dev/null) ]] || first=true
  mkdir -p "$dir"

  for p in $SNAPSHOT_FILES; do [[ -e $CONFIG/$p ]] && paths+=("$p"); done
  while read -r p; do [[ -n $p ]] && paths+=("$p"); done < <(managed_plugins)
  [[ -d $THEME_DIR ]] && paths+=("omarchy/themes/macos")

  # The theme's own wallpapers and preview come back from the repo on restore.
  local excludes=(--exclude="omarchy/themes/macos/preview.png")
  for p in "$REPO"/theme/backgrounds/*; do
    excludes+=(--exclude="omarchy/themes/macos/backgrounds/$(basename "$p")")
  done
  # Before the theme there may be nothing yet, which is a valid snapshot too.
  if (( ${#paths[@]} )); then
    tar -C "$CONFIG" "${excludes[@]}" -czf "$dir/files.tar.gz" "${paths[@]}"
  else
    tar -czf "$dir/files.tar.gz" -T /dev/null
  fi

  if $first; then
    original=true
    for p in $FEATURES; do installed "$p" && original=false; done
  fi
  jq -n --arg id "$id" --arg created "$(date -Iseconds)" --arg note "$note" \
    --arg theme "$(omarchy theme current 2>/dev/null)" \
    --argjson pinned "$first" --argjson original "$original" \
    '{id: $id, created: $created, note: $note, theme: $theme, pinned: $pinned, original: $original}' \
    > "$dir/meta.json"
  snapshot_prune
  echo "$id"
}

# Keeps the first snapshot and the newest $SNAPSHOT_KEEP others.
snapshot_prune() {
  local old
  jq -rs --argjson keep "$SNAPSHOT_KEEP" \
    '[.[] | select(.pinned | not)] | sort_by(.id) | reverse | .[$keep:][] | .id' \
    "$SNAPSHOTS"/*/meta.json 2>/dev/null | while read -r old; do
    [[ $old =~ $SNAPSHOT_ID_PATTERN ]] && rm -rf "${SNAPSHOTS:?}/$old"
  done
}

snapshot_list_json() {
  if compgen -G "$SNAPSHOTS/*/meta.json" >/dev/null; then
    jq -s 'sort_by(.id) | reverse' "$SNAPSHOTS"/*/meta.json
  else
    echo "[]"
  fi
}

snapshot_list_text() {
  snapshot_list_json | jq -r '.[] | "\(.id)  \(.created[0:16] | sub("T"; " "))  \(if .original then "Before macOS theme" else .note end)\(if .pinned then "  (kept)" else "" end)"'
}

# Puts a snapshot back: first a snapshot of now, so the restore can be undone,
# then the files, then the Omarchy theme that was current, reloaded once.
snapshot_restore() {
  local id="$1" dir="$SNAPSHOTS/$1" p theme
  [[ $id =~ $SNAPSHOT_ID_PATTERN && -f $dir/files.tar.gz ]] ||
    { echo "No backup called $id (see: ./install.sh --backups)" >&2; exit 1; }
  theme=$(jq -r '.theme // ""' "$dir/meta.json")
  local undo
  undo=$(snapshot_take "Before restoring $(jq -r '.created[0:16] | sub("T"; " ")' "$dir/meta.json")")

  for p in $SNAPSHOT_FILES; do rm -f "${CONFIG:?}/$p"; done
  while read -r p; do [[ -n $p ]] && rm -rf "${CONFIG:?}/$p"; done < <(managed_plugins)
  rm -rf "${THEME_DIR:?}"
  tar -C "$CONFIG" --no-same-owner -xzf "$dir/files.tar.gz"
  # The theme's own files, left out of snapshots.
  [[ -d $THEME_DIR ]] && cp -rn "$REPO/theme/." "$THEME_DIR/"

  if [[ -n $theme && $theme != "$(omarchy theme current 2>/dev/null)" ]]; then
    omarchy theme set "$theme"
  else
    if active; then refresh; else
      hyprctl reload >/dev/null 2>&1 || true
      omarchy restart shell >/dev/null 2>&1 || true
    fi
  fi
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
  set_json=$(jq --argjson v "$(magnification)" --arg c "$(clock_position)" '.magnification = $v | .clock = $c' <<<"$set_json")

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
    [[ -n $v ]] && args+=(--set "$f=$v")
  done
  local clock
  clock=$(jq -r '.settings.clock | strings' "$profile")
  [[ $clock =~ ^(left|center|right)$ ]] && args+=(--set "clock=$clock")
  if (( ${#args[@]} )); then
    MACOS_THEME_NO_SNAPSHOT=1 bash "$REPO/install.sh" "${args[@]}"
  fi

  # The dock's pinned apps and the widgets' place and layout.
  local key
  for key in dock widgets; do
    [[ $(jq -r --arg k "$key" '.shell[$k] | type' "$profile") == object ]] || continue
    local src=$SHELL_JSON out
    [[ -s $src ]] || src="$OMARCHY_PATH/config/omarchy/shell.json"
    out=$(mktemp "$SHELL_JSON.XXXXXX")
    jq --arg k "$key" --slurpfile p "$profile" '.[$k] = (.[$k] // {}) + $p[0].shell[$k]' "$src" > "$out" && mv "$out" "$SHELL_JSON"
  done

  if [[ -d $THEME_DIR ]]; then
    mkdir -p "$THEME_DIR/backgrounds"
    for f in "$tmp"/backgrounds/*; do [[ -f $f ]] && cp -n "$f" "$THEME_DIR/backgrounds/"; done
  fi
  rm -rf "${tmp:?}"
  say "Imported $(basename "$file")"
}
