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
#   ./install.sh --all            everything
#   ./install.sh --uninstall      undo all of the above
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
OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}"
STAMP="$(date +%s)"

LOADER_COMMENT="-- macOS theme: per-theme look overrides (look.lua). Added by omarchy-macos-theme."
LOADER_LINE='require("default.hypr.require_optional").module("omarchy.current.theme.look")'
GTK_COMMENT="/* macOS theme: blur behind see-through GTK windows. Added by omarchy-macos-theme. */"
GTK_LINE="@import url(\"file://$OMARCHY_PATH/default/gtk/glass.css\");"

OSD_ID="macos-theme.osd"
HUD_ID="macos-theme.dictation-hud"
DOCK_ID="macos-theme.dock"
SWITCHER_ID="macos-theme.switcher"

say() { printf '\033[1m==>\033[0m %s\n' "$*"; }

with_osd=false with_hud=false with_dock=false with_icons=false with_switcher=false with_wide_menu=false uninstall=false
for arg in "$@"; do
  case "$arg" in
    --osd) with_osd=true ;;
    --dictation-hud) with_hud=true ;;
    --dock) with_dock=true ;;
    --icons) with_icons=true ;;
    --switcher) with_switcher=true; with_wide_menu=true ;;
    --wide-menu) with_wide_menu=true ;;
    --all) with_osd=true; with_hud=true; with_dock=true; with_icons=true; with_switcher=true ;;
    --uninstall) uninstall=true ;;
    -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $arg (try --help)" >&2; exit 1 ;;
  esac
done

command -v omarchy >/dev/null || { echo "This needs Omarchy (the omarchy command was not found)." >&2; exit 1; }

# Remove a line and the comment line above it, keeping a backup.
remove_lines() {
  local file="$1" comment="$2" line="$3"
  [[ -f $file ]] && grep -qF "$line" "$file" || return 0
  cp "$file" "$file.bak.$STAMP"
  grep -vxF -e "$comment" -e "$line" "$file.bak.$STAMP" > "$file"
}

if $uninstall; then
  if [[ $(omarchy theme current 2>/dev/null) == "Macos" ]]; then
    echo "Switch to another theme first (omarchy theme set <name>), then run --uninstall again." >&2
    exit 1
  fi
  if [[ -d $PLUGINS_DIR/$OSD_ID ]]; then
    omarchy plugin disable "$OSD_ID" >/dev/null 2>&1 || true
    omarchy plugin enable omarchy.osd >/dev/null 2>&1 || true
    rm -rf "${PLUGINS_DIR:?}/$OSD_ID"
    say "Removed the volume capsule and restored Omarchy's own"
  fi
  if [[ -d $PLUGINS_DIR/$DOCK_ID ]]; then
    omarchy plugin disable "$DOCK_ID" >/dev/null 2>&1 || true
    omarchy plugin enable omarchy.dock >/dev/null 2>&1 || true
    rm -rf "${PLUGINS_DIR:?}/$DOCK_ID"
    say "Removed the macOS dock and restored Omarchy's own"
  fi
  # The wide menu is a clone of Omarchy's menu marked by its width comment.
  for dir in "$PLUGINS_DIR"/*.menu; do
    [[ -f $dir/Menu.qml ]] && grep -q "macOS theme: wider" "$dir/Menu.qml" || continue
    omarchy plugin disable "$(basename "$dir")" >/dev/null 2>&1 || true
    omarchy plugin enable omarchy.menu >/dev/null 2>&1 || true
    rm -rf "${dir:?}"
    say "Removed the wide menu and restored Omarchy's own"
  done
  if [[ -d $PLUGINS_DIR/$SWITCHER_ID ]]; then
    omarchy plugin disable "$SWITCHER_ID" >/dev/null 2>&1 || true
    rm -rf "${PLUGINS_DIR:?}/$SWITCHER_ID"
    say "Removed the app switcher (Alt+Tab is back to your own binding after: hyprctl reload)"
  fi
  if [[ -d $PLUGINS_DIR/$HUD_ID ]]; then
    omarchy plugin disable "$HUD_ID" >/dev/null 2>&1 || true
    rm -rf "${PLUGINS_DIR:?}/$HUD_ID"
    say "Removed the dictation HUD (turn Voxtype's own overlay back on with: voxtype config set osd.enabled true)"
  fi
  remove_lines "$LOOKNFEEL" "$LOADER_COMMENT" "$LOADER_LINE"
  remove_lines "$GTK_CSS" "$GTK_COMMENT" "$GTK_LINE"
  rm -rf "$THEME_DIR"
  say "Removed the theme. Backups of edited files end in .bak.$STAMP"
  if [[ -d $HOME/.local/share/icons/MacTahoe ]]; then
    echo "    MacTahoe icons are still installed. Remove them with:"
    echo "      rm -rf ~/.local/share/icons/MacTahoe ~/.local/share/icons/MacTahoe-light ~/.local/share/icons/MacTahoe-dark"
  fi
  exit 0
fi

# 1. The theme, as a local theme (so its .lua and ghostty.conf are kept).
if [[ -d $THEME_DIR ]]; then
  mkdir -p "$BACKUP_DIR"
  mv "$THEME_DIR" "$BACKUP_DIR/macos.$STAMP"
  say "Backed up your existing macos theme to $BACKUP_DIR/macos.$STAMP"
fi
mkdir -p "$THEME_DIR"
cp -r "$REPO/theme/." "$THEME_DIR/"
say "Installed the theme to $THEME_DIR"

# 1b. MacTahoe icons (GPL-3.0, github.com/vinceliuice/MacTahoe-icon-theme):
# only the default color, into your home folder, no password needed.
if $with_icons; then
  tmp=$(mktemp -d)
  if git clone -q --depth 1 https://github.com/vinceliuice/MacTahoe-icon-theme.git "$tmp/MacTahoe" &&
    bash "$tmp/MacTahoe/install.sh" -t default >/dev/null; then
    say "Installed the MacTahoe icon theme to ~/.local/share/icons"
  else
    echo "Could not install MacTahoe icons; keeping the default icons." >&2
  fi
  rm -rf "$tmp"
fi
# Use MacTahoe whenever it is installed (here or system-wide).
if [[ -d $HOME/.local/share/icons/MacTahoe-dark || -d /usr/share/icons/MacTahoe-dark ]]; then
  echo "MacTahoe-dark" > "$THEME_DIR/icons.theme"
fi

# 2. Load the theme's look.lua last, after your own looknfeel settings.
mkdir -p "$(dirname "$LOOKNFEEL")"
touch "$LOOKNFEEL"
if ! grep -qF 'omarchy.current.theme.look' "$LOOKNFEEL"; then
  cp "$LOOKNFEEL" "$LOOKNFEEL.bak.$STAMP"
  printf '\n%s\n%s\n' "$LOADER_COMMENT" "$LOADER_LINE" >> "$LOOKNFEEL"
  say "Added the look.lua loader to $LOOKNFEEL"
fi

# 3. Let GTK apps such as Files ask Hyprland for blur.
mkdir -p "$(dirname "$GTK_CSS")"
touch "$GTK_CSS"
if ! grep -qF 'default/gtk/glass.css' "$GTK_CSS"; then
  cp "$GTK_CSS" "$GTK_CSS.bak.$STAMP"
  printf '%s\n%s\n' "$GTK_COMMENT" "$GTK_LINE" >> "$GTK_CSS"
  say "Added GTK blur to $GTK_CSS (reopen GTK apps to see it)"
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
if $with_osd; then
  install_plugin "$OSD_ID"
  omarchy plugin disable omarchy.osd >/dev/null 2>&1 || true
  say "Installed the frosted volume capsule (replaces Omarchy's own popup)"
fi
if $with_dock; then
  install_plugin "$DOCK_ID"
  omarchy plugin disable omarchy.dock >/dev/null 2>&1 || true
  say "Installed the macOS dock (minimized windows sit after a divider at its end)"
fi
if $with_switcher; then
  install_plugin "$SWITCHER_ID"
  say "Installed the switchers (Alt+Tab apps, Super+Tab workspaces, while this theme is active)"
fi
fc-list : family | grep -q "^Inter" || echo "    The theme uses the Inter font, which is not installed. Install it with: sudo pacman -S inter-font" >&2

if $with_wide_menu; then
  # Clone the menu of the Omarchy version installed here, then patch it (width,
  # magnifying glass, "Search"), so it matches this Omarchy's menu otherwise.
  menu_dir=$(ls -d "$PLUGINS_DIR"/*.menu 2>/dev/null | while read -r d; do grep -q '"clonedFrom": "omarchy.menu"' "$d/manifest.json" 2>/dev/null && echo "$d"; done | head -n1)
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
if $with_hud; then
  install_plugin "$HUD_ID"
  say "Installed the dictation HUD"
  if command -v voxtype >/dev/null; then
    echo "    Voxtype draws its own overlay too. To show only the HUD, run:"
    echo "      voxtype config set osd.enabled false && systemctl --user restart voxtype"
  else
    echo "    Voxtype isn't installed; the HUD stays hidden until it is."
  fi
fi

# 5. Apply. Re-applying the active theme would move to its next wallpaper, so
# when it is already active, refresh it in place instead.
if [[ $(omarchy theme current 2>/dev/null) == "Macos" ]]; then
  cp -r "$THEME_DIR/." "$HOME/.local/state/omarchy/current/theme/"
  omarchy-theme-set-gnome >/dev/null 2>&1 || true
  hyprctl reload >/dev/null
  omarchy restart shell >/dev/null 2>&1 || true
else
  omarchy theme set macos
fi
say "Done. The bar, menus and popups pick up the theme now; restart the shell if they don't: omarchy restart shell"
