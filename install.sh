#!/usr/bin/env bash
# Install (or remove) the macOS theme for Omarchy.
#
#   ./install.sh                  theme only
#   ./install.sh --osd            + frosted volume/brightness capsule
#   ./install.sh --dictation-hud  + Voxtype dictation pill
#   ./install.sh --dock           + macOS dock (running dots, Downloads stack, Trash)
#   ./install.sh --icons          + MacTahoe macOS icon theme (from GitHub)
#   ./install.sh --switcher       + app switcher (Alt+Tab) and workspace switcher (Super+Tab)
#   ./install.sh --wide-menu      + Spotlight-like Omarchy menu: wider, magnifying glass, "Search"
#   ./install.sh --menubar        + macOS menu bar: Inter, bold app name, Control Center, shade
#   ./install.sh --all            everything
#   ./install.sh --uninstall      undo all of the above (MacTahoe icons stay)
#
#   ./install.sh --add dock       only that piece, without the theme
#   ./install.sh --remove dock    remove only that piece
#   ./install.sh --status [--json]  which pieces are installed, and the settings
#   ./install.sh --set glass=0.8  how solid windows are, 0.5 to 1 (1 is solid)
#   ./install.sh --set magnification=1.5  how far dock icons grow, 1 (off) to 2
#   Pieces: theme rows icons wide-menu dock switcher osd dictation-hud menubar
#
# Why a script and not `omarchy theme install <url>`: themes installed from git
# have their .lua files and ghostty.conf stripped for safety, and those carry
# the glass, title bars and gaps. This copies the theme in as a local theme.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
THEME_DIR="$CONFIG/omarchy/themes/macos"
# Outside themes/, or every backup would show up in the theme picker.
BACKUP_DIR="$CONFIG/omarchy/macos-theme-backups"
PLUGINS_DIR="$CONFIG/omarchy/plugins"
LOOKNFEEL="$CONFIG/hypr/looknfeel.lua"
GTK_CSS="$CONFIG/gtk-4.0/gtk.css"
SHELL_JSON="$CONFIG/omarchy/shell.json"
OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}"
STAMP="$(date +%s)"

LOADER_COMMENT="-- macOS theme: per-theme look overrides (look.lua). Added by omarchy-macos-theme."
LOADER_LINE='require("default.hypr.require_optional").module("omarchy.current.theme.look")'
GTK_COMMENT="/* macOS theme: blur behind see-through GTK windows. Added by omarchy-macos-theme. */"
GTK_LINE="@import url(\"file://$OMARCHY_PATH/default/gtk/glass.css\");"
ROWS_COMMENT="/* macOS theme: Finder-style list rows while the theme is active. Added by omarchy-macos-theme. */"
ROWS_LINE="@import url(\"file://$HOME/.local/state/omarchy/current/theme/gtk.css\");"

OSD_ID="macos-theme.osd"
HUD_ID="macos-theme.dictation-hud"
DOCK_ID="macos-theme.dock"
MENUBAR_IDS="macos-theme.menubar macos-theme.app-name macos-theme.control-center"
# The bar widgets the Control Center stands in for. They wait in the bar's tray
# drawer rather than leaving the bar, since their panels live in them.
CONTROL_CENTER_WIDGETS="omarchy.network omarchy.bluetooth omarchy.tailscale omarchy.audio omarchy.monitor omarchy.power"
SWITCHER_ID="macos-theme.switcher"

say() { printf '\033[1m==>\033[0m %s\n' "$*"; }

# Each piece, by the name --add, --remove and --status use.
FEATURES="theme rows icons wide-menu dock switcher osd dictation-hud menubar"
declare -A add=() remove=() settings=()
status=false json=false legacy=false
(( $# )) || legacy=true
while (( $# )); do
  case "$1" in
    --osd) add[osd]=1; legacy=true ;;
    --dictation-hud) add[dictation-hud]=1; legacy=true ;;
    --dock) add[dock]=1; legacy=true ;;
    --icons) add[icons]=1; legacy=true ;;
    --switcher) add[switcher]=1; add[wide-menu]=1; legacy=true ;;
    --wide-menu) add[wide-menu]=1; legacy=true ;;
    --menubar) add[menubar]=1; legacy=true ;;
    --all) for f in osd dictation-hud dock icons switcher wide-menu menubar; do add[$f]=1; done; legacy=true ;;
    --add|--remove)
      [[ " $FEATURES " == *" ${2:-} "* ]] || { echo "Unknown feature: ${2:-} (one of: $FEATURES)" >&2; exit 1; }
      if [[ $1 == --add ]]; then add[$2]=1; else remove[$2]=1; fi
      shift ;;
    # MacTahoe stays, as it always has: it may serve other themes too.
    --set)
      [[ ${2:-} =~ ^(glass|magnification)=([0-9]+(\.[0-9]+)?)$ ]] &&
        awk -v k="${BASH_REMATCH[1]}" -v v="${BASH_REMATCH[2]}" 'BEGIN { exit !(k == "glass" ? v >= 0.5 && v <= 1 : v >= 1 && v <= 2) }' ||
        { echo "Unknown setting: ${2:-} (glass=0.5 to 1, or magnification=1 to 2)" >&2; exit 1; }
      settings[${BASH_REMATCH[1]}]=${BASH_REMATCH[2]}
      shift ;;
    --uninstall) for f in $FEATURES; do [[ $f == icons ]] || remove[$f]=1; done ;;
    --status) status=true ;;
    --json) json=true ;;
    -h|--help) sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1 (try --help)" >&2; exit 1 ;;
  esac
  shift
done
# The old options install the theme itself too; --add installs only what it names.
if $legacy; then add[theme]=1; add[rows]=1; fi

command -v omarchy >/dev/null || { echo "This needs Omarchy (the omarchy command was not found)." >&2; exit 1; }

# The wide menu is a clone of Omarchy's menu marked by its width comment.
wide_menus() {
  local dir
  for dir in "$PLUGINS_DIR"/*.menu; do
    [[ -f $dir/Menu.qml ]] && grep -q "macOS theme: wider" "$dir/Menu.qml" && echo "$dir"
  done
  return 0
}

installed() {
  case "$1" in
    theme) [[ -d $THEME_DIR ]] ;;
    rows) grep -qsF "$ROWS_LINE" "$GTK_CSS" ;;
    icons) [[ -d $HOME/.local/share/icons/MacTahoe-dark ]] ;;
    wide-menu) [[ -n $(wide_menus) ]] ;;
    dock) [[ -d $PLUGINS_DIR/$DOCK_ID ]] ;;
    switcher) [[ -d $PLUGINS_DIR/$SWITCHER_ID ]] ;;
    osd) [[ -d $PLUGINS_DIR/$OSD_ID ]] ;;
    dictation-hud) [[ -d $PLUGINS_DIR/$HUD_ID ]] ;;
    menubar) [[ -d $PLUGINS_DIR/macos-theme.menubar ]] ;;
  esac
}

active() { [[ $(omarchy theme current 2>/dev/null) == "Macos" ]]; }

# Glass is the opacity look.lua gives every window; magnification is a key of
# the dock's section of shell.json, which the dock follows live.
GLASS_RULE='^(o\.window\("\.\*", \{ opacity = ")([0-9.]+) [0-9.]+'
glass() { sed -nE "s/$GLASS_RULE.*/\2/p" "$THEME_DIR/look.lua" 2>/dev/null || true; }
set_glass() { sed -i -E "s/$GLASS_RULE/\1$1 $1/" "$THEME_DIR/look.lua"; }
magnification() {
  local m
  m=$(jq '.dock.magnification | numbers' "$SHELL_JSON" 2>/dev/null) || true
  echo "${m:-1.75}"
}
set_magnification() {
  # A missing shell.json means Omarchy's defaults, as `omarchy dock` treats it.
  local src=$SHELL_JSON tmp
  [[ -s $src ]] || src="$OMARCHY_PATH/config/omarchy/shell.json"
  mkdir -p "$(dirname "$SHELL_JSON")"
  tmp=$(mktemp)
  jq -S --argjson m "$1" '.dock.magnification = $m' "$src" >"$tmp" && mv "$tmp" "$SHELL_JSON"
}

if $status; then
  if $json; then
    out=""
    for f in $FEATURES; do
      out+="$([[ -n $out ]] && echo ,)\"$f\":$(installed "$f" && echo true || echo false)"
    done
    g=$(glass)
    printf '{"active":%s,"features":{%s},"settings":{"glass":%s,"magnification":%s}}\n' \
      "$(active && echo true || echo false)" "$out" "${g:-0.7}" "$(magnification)"
  else
    active && echo "The macOS theme is the current theme."
    for f in $FEATURES; do
      printf '%-14s %s\n' "$f" "$(installed "$f" && echo installed || echo "not installed")"
    done
    g=$(glass)
    printf '%-14s %s\n' glass "${g:-0.7}" magnification "$(magnification)"
  fi
  exit 0
fi

# Re-applying the active theme would move to its next wallpaper, so refresh it
# in place instead.
refresh() {
  cp -r "$THEME_DIR/." "$HOME/.local/state/omarchy/current/theme/"
  omarchy-theme-set-gnome >/dev/null 2>&1 || true
  hyprctl reload >/dev/null
  omarchy restart shell >/dev/null 2>&1 || true
}

# Remove a line and the comment line above it, keeping a backup.
remove_lines() {
  local file="$1" comment="$2" line="$3"
  [[ -f $file ]] && grep -qF "$line" "$file" || return 0
  cp "$file" "$file.bak.$STAMP"
  # grep exits 1 when no lines are left, which is fine here.
  grep -vxF -e "$comment" -e "$line" "$file.bak.$STAMP" > "$file" || true
}

remove_osd() {
  omarchy plugin disable "$OSD_ID" >/dev/null 2>&1 || true
  omarchy plugin enable omarchy.osd >/dev/null 2>&1 || true
  rm -rf "${PLUGINS_DIR:?}/$OSD_ID"
  say "Removed the volume capsule and restored Omarchy's own"
}
remove_dock() {
  omarchy plugin disable "$DOCK_ID" >/dev/null 2>&1 || true
  omarchy plugin enable omarchy.dock >/dev/null 2>&1 || true
  rm -rf "${PLUGINS_DIR:?}/$DOCK_ID"
  say "Removed the macOS dock and restored Omarchy's own"
}
remove_wide_menu() {
  local dir
  for dir in $(wide_menus); do
    omarchy plugin disable "$(basename "$dir")" >/dev/null 2>&1 || true
    omarchy plugin enable omarchy.menu >/dev/null 2>&1 || true
    rm -rf "${dir:?}"
  done
  say "Removed the wide menu and restored Omarchy's own"
}
remove_switcher() {
  omarchy plugin disable "$SWITCHER_ID" >/dev/null 2>&1 || true
  rm -rf "${PLUGINS_DIR:?}/$SWITCHER_ID"
  say "Removed the app switcher (Alt+Tab is back to your own binding after: hyprctl reload)"
}
remove_menubar() {
  local id after=omarchy.tray
  for id in $MENUBAR_IDS; do
    omarchy plugin disable "$id" >/dev/null 2>&1 || true
    rm -rf "${PLUGINS_DIR:?}/$id"
  done
  # Omarchy's widgets back to its default bar: the clock in the middle, the
  # system icons in a row after the tray.
  omarchy bar move omarchy.clock --section center >/dev/null 2>&1 || true
  omarchy bar move omarchy.tray --section right --index 0 >/dev/null 2>&1 || true
  for id in omarchy.keyboard-layout omarchy.agents omarchy.bluetooth omarchy.network omarchy.tailscale omarchy.audio omarchy.monitor omarchy.power; do
    omarchy bar move "$id" --after "$after" >/dev/null 2>&1 && after=$id
  done
  say "Removed the menu bar look and put the system widgets back on the bar"
}
remove_dictation_hud() {
  omarchy plugin disable "$HUD_ID" >/dev/null 2>&1 || true
  rm -rf "${PLUGINS_DIR:?}/$HUD_ID"
  say "Removed the dictation HUD (turn Voxtype's own overlay back on with: voxtype config set osd.enabled true)"
}
remove_rows() {
  remove_lines "$GTK_CSS" "$ROWS_COMMENT" "$ROWS_LINE"
  say "Removed striped Files rows (reopen Files to see it)"
}
remove_icons() {
  rm -rf "$HOME"/.local/share/icons/MacTahoe{,-light,-dark}
  if [[ -d $THEME_DIR ]]; then
    cp "$REPO/theme/icons.theme" "$THEME_DIR/icons.theme"
    if active; then refresh; fi
  fi
  say "Removed the MacTahoe icons"
}
# Moves the theme folder aside into a backup of its own, named in $kept (two
# runs in the same second must not land in one folder).
kept=""
keep_theme() {
  mkdir -p "$BACKUP_DIR"
  kept=$(mktemp -d "$BACKUP_DIR/macos.$STAMP.XXX")
  mv -T "$THEME_DIR" "$kept"
}

remove_theme() {
  remove_lines "$LOOKNFEEL" "$LOADER_COMMENT" "$LOADER_LINE"
  remove_lines "$GTK_CSS" "$GTK_COMMENT" "$GTK_LINE"
  # Kept, not deleted: it may hold wallpapers and files of your own.
  keep_theme
  say "Removed the theme (kept in $kept)"
}

if (( ${#remove[@]} )); then
  if [[ -n ${remove[theme]:-} ]] && active; then
    echo "Switch to another theme first (omarchy theme set <name>), then remove the theme again." >&2
    exit 1
  fi
  # Plugins before the theme they sit on.
  for f in osd dock wide-menu switcher menubar dictation-hud rows icons theme; do
    if [[ -n ${remove[$f]:-} ]] && installed "$f"; then "remove_${f//-/_}"; fi
  done
  say "Done. Backups of edited files end in .bak.$STAMP"
  if [[ -z ${remove[icons]:-} ]] && installed icons && [[ -n ${remove[theme]:-} ]]; then
    echo "    MacTahoe icons are still installed. Remove them with: ./install.sh --remove icons"
  fi
  (( ${#add[@]} + ${#settings[@]} )) || exit 0
fi

want() { [[ -n ${add[$1]:-} ]]; }

# 1. The theme, as a local theme (so its .lua and ghostty.conf are kept).
if want theme; then
  old_glass=$(glass)
  if [[ -d $THEME_DIR ]]; then
    keep_theme
    say "Backed up your existing macos theme to $kept"
  fi
  mkdir -p "$THEME_DIR"
  cp -r "$REPO/theme/." "$THEME_DIR/"
  # Wallpapers and files you added stay; the theme's own files are the new ones.
  [[ -n $kept ]] && cp -rn "$kept/." "$THEME_DIR/"
  # So does the glass you chose.
  [[ -n $old_glass ]] && set_glass "$old_glass"
  say "Installed the theme to $THEME_DIR"
fi

# 1b. MacTahoe icons (GPL-3.0, github.com/vinceliuice/MacTahoe-icon-theme):
# only the default color, into your home folder, no password needed.
if want icons; then
  tmp=$(mktemp -d)
  if git clone -q --depth 1 https://github.com/vinceliuice/MacTahoe-icon-theme.git "$tmp/MacTahoe" &&
    bash "$tmp/MacTahoe/install.sh" -t default >/dev/null; then
    say "Installed the MacTahoe icon theme to ~/.local/share/icons"
    # Finder lists folders and files with small color icons (blue folders, paper
    # documents), but below 32px MacTahoe draws gray outlines and flat glyphs:
    # use its large icons at those sizes too. The sidebar uses -symbolic icons,
    # so give the folders that have none (Projects) one.
    for t in "$HOME"/.local/share/icons/MacTahoe{,-dark,-light}; do
      [[ -d $t/places/scalable ]] || continue
      for f in "$t"/mimes/{16,22,24}/*.svg "$t"/places/{16,22,24}/{folder,inode-directory}*.svg; do
        src=${f%/*/*}/scalable/${f##*/}
        [[ -f $src ]] || src=$t/places/scalable/${f##*/}
        [[ -f $src ]] && cp --remove-destination "$src" "$f"
      done
      for f in "$t"/places/scalable/folder-*.svg; do
        sym=$t/places/symbolic/$(basename "$f" .svg)-symbolic.svg
        [[ -e $sym || ! -f $t/places/symbolic/folder-symbolic.svg ]] || cp "$t/places/symbolic/folder-symbolic.svg" "$sym"
      done
      gtk-update-icon-cache -f -q "$t" 2>/dev/null || true
    done
  else
    echo "Could not install MacTahoe icons; keeping the default icons." >&2
  fi
  rm -rf "$tmp"
fi
# Use MacTahoe whenever it is installed (here or system-wide).
if [[ -d $THEME_DIR ]] && [[ -d $HOME/.local/share/icons/MacTahoe-dark || -d /usr/share/icons/MacTahoe-dark ]]; then
  echo "MacTahoe-dark" > "$THEME_DIR/icons.theme"
fi

# 2. Load the theme's look.lua last, after your own looknfeel settings.
mkdir -p "$(dirname "$LOOKNFEEL")" "$(dirname "$GTK_CSS")"
touch "$LOOKNFEEL" "$GTK_CSS"
if want theme && ! grep -qF 'omarchy.current.theme.look' "$LOOKNFEEL"; then
  cp "$LOOKNFEEL" "$LOOKNFEEL.bak.$STAMP"
  printf '\n%s\n%s\n' "$LOADER_COMMENT" "$LOADER_LINE" >> "$LOOKNFEEL"
  say "Added the look.lua loader to $LOOKNFEEL"
fi

# 3. Let GTK apps such as Files ask Hyprland for blur, and stripe Files lists.
if want theme && ! grep -qF 'default/gtk/glass.css' "$GTK_CSS"; then
  cp "$GTK_CSS" "$GTK_CSS.bak.$STAMP"
  printf '%s\n%s\n' "$GTK_COMMENT" "$GTK_LINE" >> "$GTK_CSS"
  say "Added GTK blur to $GTK_CSS (reopen GTK apps to see it)"
fi
# Striped rows in Files, from the theme's gtk.css, so only while it is active.
if want rows && ! grep -qF "$ROWS_LINE" "$GTK_CSS"; then
  cp "$GTK_CSS" "$GTK_CSS.bak.$STAMP"
  printf '%s\n%s\n' "$ROWS_COMMENT" "$ROWS_LINE" >> "$GTK_CSS"
  say "Added striped Files rows to $GTK_CSS (reopen Files to see them)"
fi

# 4. Optional plugins.
install_plugin() {
  rm -rf "${PLUGINS_DIR:?}/$1"
  mkdir -p "$PLUGINS_DIR"
  cp -r "$REPO/plugins/$1" "$PLUGINS_DIR/$1"
  # The shell only knows plugins it has scanned, and the rescan finishes in the
  # background, so retry the enable for a few seconds.
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
  local tries=0
  until omarchy plugin enable "$1" >/dev/null 2>&1; do
    (( ++tries < 20 )) || { echo "Could not enable $1; try: omarchy plugin enable $1" >&2; return 1; }
    sleep 0.25
  done
}
if want osd; then
  install_plugin "$OSD_ID"
  omarchy plugin disable omarchy.osd >/dev/null 2>&1 || true
  say "Installed the frosted volume capsule (replaces Omarchy's own popup)"
fi
if want dock; then
  install_plugin "$DOCK_ID"
  omarchy plugin disable omarchy.dock >/dev/null 2>&1 || true
  say "Installed the macOS dock (minimized windows sit after a divider at its end)"
fi
if want switcher; then
  install_plugin "$SWITCHER_ID"
  say "Installed the switchers (Alt+Tab apps, Super+Tab workspaces, while this theme is active)"
fi
if want menubar; then
  for id in $MENUBAR_IDS; do install_plugin "$id"; done
  # The bold app name follows the menu button, as on macOS, and Control Center
  # sits by the clock; the widgets it stands in for go to the tray drawer.
  omarchy bar put macos-theme.app-name --section left >/dev/null 2>&1 || true
  omarchy bar move macos-theme.app-name --before omarchy.workspaces >/dev/null 2>&1 || true
  omarchy bar move omarchy.clock --section right >/dev/null 2>&1 || true
  omarchy bar put macos-theme.control-center >/dev/null 2>&1 || true
  omarchy bar move macos-theme.control-center --before omarchy.clock >/dev/null 2>&1 || true
  for id in $CONTROL_CENTER_WIDGETS; do
    omarchy bar move "$id" --section tray >/dev/null 2>&1 || true
  done
  # Omarchy's other widgets as macOS keeps their like: status in the middle,
  # the input menu by Control Center, the bell past the clock. Widgets from
  # other plugins stay where their owner put them.
  for move in \
    "omarchy.tray --section right --index 0" \
    "omarchy.keyboard-layout --before macos-theme.control-center" \
    "omarchy.agents --section tray" \
    "omarchy.indicators --section centerBegin" \
    "omarchy.elsewhen --section centerEnd --index 0" \
    "omarchy.weather --after omarchy.elsewhen" \
    "omarchy.system-update --after omarchy.weather" \
    "jankeesvw.notification-center --after omarchy.clock"; do
    omarchy bar move $move >/dev/null 2>&1 || true
  done
  say "Installed the macOS menu bar (Inter, app name, Control Center, a shade for legibility)"
fi
[[ -n $(fc-list Inter) ]] || echo "    The theme uses the Inter font, which is not installed. Install it with: sudo pacman -S inter-font" >&2

if want wide-menu; then
  # Clone the menu of the Omarchy version installed here, then patch it (width,
  # magnifying glass, "Search"), so it matches this Omarchy's menu otherwise.
  # No clone yet fails the lookup, which only means making one.
  menu_dir=$(ls -d "$PLUGINS_DIR"/*.menu 2>/dev/null | while read -r d; do grep -q '"clonedFrom": "omarchy.menu"' "$d/manifest.json" 2>/dev/null && echo "$d"; done | head -n1) || true
  if [[ -z $menu_dir ]]; then
    menu_dir=$(omarchy plugin clone omarchy.menu 2>/dev/null | sed -n 's/^Cloned omarchy.menu to \(.*\) and switched.*/\1/p')
  fi
  if [[ -n $menu_dir && -f $menu_dir/Menu.qml ]]; then
    perl -0pi "$REPO/menu-patch.pl" "$menu_dir/Menu.qml"
    grep -q "Style.space(560)), panel.width" "$menu_dir/Menu.qml" && say "Widened the Omarchy menu, with a Spotlight search line" || echo "    Could not patch this Omarchy version's menu; it keeps its own look." >&2
  else
    echo "    Could not clone Omarchy's menu; it keeps its own width." >&2
  fi
fi
if want dictation-hud; then
  install_plugin "$HUD_ID"
  say "Installed the dictation HUD"
  if command -v voxtype >/dev/null; then
    echo "    Voxtype draws its own overlay too. To show only the HUD, run:"
    echo "      voxtype config set osd.enabled false && systemctl --user restart voxtype"
  else
    echo "    Voxtype isn't installed; the HUD stays hidden until it is."
  fi
fi

# 4b. Settings.
if [[ -n ${settings[glass]:-} ]]; then
  installed theme || { echo "Install the theme first (--add theme), then set its glass." >&2; exit 1; }
  set_glass "${settings[glass]}"
  say "Set the glass to ${settings[glass]}"
fi
if [[ -n ${settings[magnification]:-} ]]; then
  set_magnification "${settings[magnification]}"
  say "Set the dock's magnification to ${settings[magnification]}"
fi

# 5. Apply: refresh the active theme in place, or switch to it when it was asked for.
# The dock follows shell.json itself, so magnification alone needs no refresh.
if active && { (( ${#add[@]} )) || [[ -n ${settings[glass]:-} ]]; }; then
  refresh
elif want theme; then
  omarchy theme set macos
fi
say "Done. The bar, menus and popups pick up the theme now; restart the shell if they don't: omarchy restart shell"
