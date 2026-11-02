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
#   ./install.sh --bar-icons      + macOS icons for the bar's Network, Bluetooth, Audio and Display
#   ./install.sh --lock           + macOS lock screen: date, large clock, account picture, glass field
#   ./install.sh --widgets        + desktop widgets: clock, calendar, weather, now playing
#   ./install.sh --all            everything
#   ./install.sh --uninstall      undo all of the above (MacTahoe icons stay)
#
#   ./install.sh --add dock       only that piece, without the theme
#   ./install.sh --remove dock    remove only that piece
#   ./install.sh --status [--json]  which pieces are installed, and the settings
#   ./install.sh --set glass=0.8  how solid windows are, 0.5 to 1 (1 is solid)
#   ./install.sh --set web-glass=0.9  the same for browsers, web apps and Electron apps
#   ./install.sh --set snapping=0  turn off snapping windows to halves and corners (1: on)
#   ./install.sh --set blur=15     how strong the frosted blur is, 0 (off) to 20; the theme's is 10
#   ./install.sh --set clock=center  where the bar's clock sits: left, center or right
#   ./install.sh --set volume-hud=top  where the volume panel shows: bottom (middle,
#                                 the theme's) or top (right, under the bar)
#   ./install.sh --set dictation-hud=top  the same for the dictation panel
#   ./install.sh --bar [--json]   the bar's items by section, and the hidden ones
#   ./install.sh --bar-layout '{"sections":{"right":["omarchy.clock",…],…},"hidden":["omarchy.weather"]}'
#                                 show, hide and order the bar's items (sections: left,
#                                 centerBegin, center, centerEnd, right, tray)
#   ./install.sh --set magnification=1.5  how far dock icons grow, 1 (off) to 2
#   ./install.sh --set dock-size=56  how big dock icons are, 32 to 80 points; 48 by default
#   ./install.sh --set drop-follow=0  a window dropped onto another workspace goes alone
#                                 (1, the theme's: you go along with it)
#   ./install.sh --set title-bars=0  turn off the title bars with traffic lights (1: on)
#   ./install.sh --set traffic-lights=16  how big the traffic lights are, 10 to 20; 14 by default
#   ./install.sh --preview --set blur=15  show settings at once, for a slider being dragged:
#                                  no snapshot or theme refresh; blur and the dock's
#                                  settings change in place until Apply, glass reloads
#                                  Hyprland
#   ./install.sh --show-widgets clock,weather  which desktop widgets show (clock, calendar,
#                                 weather, playing); at least one
#   ./install.sh --switch-to "Tokyo Night" --uninstall --remove icons  remove all of it,
#                                 switching to that theme first if the macOS theme is current
#
#   Every change takes a snapshot first, so it can be undone (the first one is kept for good):
#   ./install.sh --backups [--json]   the snapshots, newest first
#   ./install.sh --backup             take one now
#   ./install.sh --restore <id>       put one back (taking a snapshot of now first); shell.json,
#                                     looknfeel.lua and gtk.css come back whole, so edits you
#                                     made to them since go too
#   ./install.sh --export <file|dir>  your choices in one file, for another computer or a new install
#   ./install.sh --import <file>      apply an export here
#   Pieces: theme rows icons wide-menu dock switcher osd dictation-hud menubar bar-icons lock widgets
#
#   What it did goes to stdout; warnings and errors to stderr. So a run that
#   succeeds (exit 0) may still have warned, about a piece it skipped, say.
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
# The bar's arrangement when the menu bar was last removed, to come back with
# it (a piece removed and added again keeps your settings).
BAR_REMEMBERED="$BACKUP_DIR/bar-layout.json"
# The plugins that were on before the theme's first piece, and the bar before
# the menu bar, so removing them gives back exactly that.
BEFORE_THEME="$BACKUP_DIR/plugins-before-theme.json"
BAR_BEFORE="$BACKUP_DIR/bar-before-menubar.json"
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
# Omdrop (AirDrop for Omarchy) included: Control Center has its switch.
CONTROL_CENTER_WIDGETS="omarchy.network omarchy.bluetooth omarchy.tailscale omarchy.audio omarchy.monitor omarchy.power netmojo.omdrop"
SWITCHER_ID="macos-theme.switcher"
WIDGETS_ID="macos-theme.widgets"
# The desktop widgets, as the widgets' WidgetsModel.js names them.
DESKTOP_WIDGETS="clock calendar weather playing"
# It gives Omarchy's own widgets macOS icons from the bar, unseen there, so
# the arrangement leaves it out.
BAR_ICONS_ID="macos-theme.bar-icons"

say() { printf '\033[1m==>\033[0m %s\n' "$*"; }

# Each piece, by the name --add, --remove and --status use.
FEATURES="theme rows icons wide-menu dock switcher osd dictation-hud menubar bar-icons lock widgets"
declare -A add=() remove=() settings=()
status=false json=false preview=false legacy=false switch_to="" mode="" mode_arg="" bar_layout="" show_widgets=""
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
    --bar-icons) add[bar-icons]=1; legacy=true ;;
    --lock) add[lock]=1; legacy=true ;;
    --widgets) add[widgets]=1; legacy=true ;;
    --all) for f in osd dictation-hud dock icons switcher wide-menu menubar bar-icons lock widgets; do add[$f]=1; done; legacy=true ;;
    --add|--remove)
      [[ " $FEATURES " == *" ${2:-} "* ]] || { echo "Unknown feature: ${2:-} (one of: $FEATURES)" >&2; exit 1; }
      if [[ $1 == --add ]]; then add[$2]=1; else remove[$2]=1; fi
      shift ;;
    # MacTahoe stays, as it always has: it may serve other themes too.
    --set)
      if [[ ${2:-} =~ ^clock=(left|center|right)$ ]]; then
        settings[clock]=${BASH_REMATCH[1]}
        shift; shift; continue
      fi
      if [[ ${2:-} =~ ^(volume-hud|dictation-hud)=(bottom|top)$ ]]; then
        settings[${BASH_REMATCH[1]}]=${BASH_REMATCH[2]}
        shift; shift; continue
      fi
      [[ ${2:-} =~ ^(glass|web-glass|magnification|dock-size|snapping|drop-follow|title-bars|traffic-lights|blur)=([0-9]+(\.[0-9]+)?)$ ]] &&
        awk -v k="${BASH_REMATCH[1]}" -v v="${BASH_REMATCH[2]}" 'BEGIN {
          exit !(k == "magnification" ? v >= 1 && v <= 2 : k == "dock-size" ? v ~ /^[0-9]+$/ && v >= 32 && v <= 80 : k == "snapping" || k == "drop-follow" || k == "title-bars" ? v == "0" || v == "1" : k == "traffic-lights" ? v ~ /^[0-9]+$/ && v >= 10 && v <= 20 : k == "blur" ? v ~ /^[0-9]+$/ && v <= 20 : v >= 0.5 && v <= 1)
        }' ||
        { echo "Unknown setting: ${2:-} (glass or web-glass=0.5 to 1, magnification=1 to 2, dock-size=32 to 80, snapping, drop-follow or title-bars=0 or 1, traffic-lights=10 to 20, blur=0 to 20, clock=left, center or right, volume-hud or dictation-hud=bottom or top)" >&2; exit 1; }
      settings[${BASH_REMATCH[1]}]=${BASH_REMATCH[2]}
      shift ;;
    --switch-to) switch_to=${2:-}; [[ -n $switch_to ]] || { echo "--switch-to needs a theme name" >&2; exit 1; }; shift ;;
    --uninstall) for f in $FEATURES; do [[ $f == icons ]] || remove[$f]=1; done ;;
    --status) status=true ;;
    --backups) mode=backups ;;
    --bar) mode=bar ;;
    --bar-layout)
      bar_layout=${2:-}
      [[ -n $bar_layout ]] || { echo "--bar-layout needs a layout (try --help)" >&2; exit 1; }
      shift ;;
    --show-widgets)
      show_widgets=${2:-}
      [[ -n ${show_widgets//,/} ]] || { echo "--show-widgets needs at least one of: ${DESKTOP_WIDGETS// /, }" >&2; exit 1; }
      for w in ${show_widgets//,/ }; do
        [[ " $DESKTOP_WIDGETS " == *" $w "* ]] || { echo "Unknown widget: $w (one of: ${DESKTOP_WIDGETS// /, })" >&2; exit 1; }
      done
      shift ;;
    --backup) mode=backup ;;
    --restore|--export|--import)
      mode=${1#--}; mode_arg=${2:-}
      [[ -n $mode_arg ]] || { echo "$1 needs a value (try --help)" >&2; exit 1; }
      shift ;;
    --json) json=true ;;
    --preview) preview=true ;;
    -h|--help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; exit 0 ;;
    *) echo "Unknown option: $1 (try --help)" >&2; exit 1 ;;
  esac
  shift
done
# The old options install the theme itself too; --add installs only what it names.
if $legacy; then add[theme]=1; add[rows]=1; fi

command -v omarchy >/dev/null || { echo "This needs Omarchy (the omarchy command was not found)." >&2; exit 1; }

# The wide menu, the bar's workspaces and the lock screen are clones of
# Omarchy's plugins. The theme's own clones carry $OWN_MARK; ones it made before
# that are known by its patch. Clones of your own are never touched.
OWN_MARK=".macos-theme"
# theme_clones <omarchy id> <patched file> <patch mark>: their folders.
theme_clones() {
  local dir
  for dir in "$PLUGINS_DIR"/*; do
    grep -qs "\"clonedFrom\": \"$1\"" "$dir/manifest.json" || continue
    [[ -e $dir/$OWN_MARK ]] || grep -qsF "$3" "$dir/$2" && echo "$dir"
  done
  return 0
}
# theme_clone <omarchy id> <patched file> <patch mark>: the theme's clone,
# made if there is none yet, and its folder printed. Omarchy names every clone
# after you, so one of your own takes that name: then the piece is skipped.
theme_clone() {
  local dir mine="$PLUGINS_DIR/${USER:-$(id -un)}.${1#omarchy.}"
  dir=$(theme_clones "$@" | head -n1)
  if [[ -z $dir ]]; then
    if [[ -e $mine ]]; then
      echo "    $(basename "$mine") is a clone of $1 of your own, so the theme leaves it as it is; move it aside to use the theme's." >&2
      return 1
    fi
    omarchy plugin clone "$1" >/dev/null 2>&1 || true
    dir=$mine
    [[ -d $dir ]] || return 1
  fi
  touch "$dir/$OWN_MARK"
  echo "$dir"
}

WIDE_MARK="macOS theme: wider"
wide_menus() { theme_clones omarchy.menu Menu.qml "$WIDE_MARK"; }

# The bar's workspaces are a clone of Omarchy's widget, patched by
# workspaces-patch.pl so a right-click opens a layout menu (WorkspaceMenu.qml).
WORKSPACES_MARK="macOS theme: a click"
workspaces_clones() { theme_clones omarchy.workspaces Workspaces.qml "$WORKSPACES_MARK"; }

# The lock screen is a clone of Omarchy's lock with the macOS LockView.qml.
LOCK_MARK="The macOS lock screen"
macos_locks() { theme_clones omarchy.lock LockView.qml "$LOCK_MARK"; }

# A MacTahoe folder the theme installed: marked, or (installed before the
# mark) with the large folder icons it copies over the small ones.
theme_icons() {
  [[ -e $1/$OWN_MARK ]] || cmp -s "$1/places/16/folder.svg" "$1/places/scalable/folder.svg"
}
# None of the theme's pieces is installed.
none_installed() {
  local f
  for f in $FEATURES; do installed "$f" && return 1; done
  return 0
}

installed() {
  case "$1" in
    theme) [[ -d $THEME_DIR ]] ;;
    rows) grep -qsF "$ROWS_LINE" "$GTK_CSS" ;;
    icons) theme_icons "$HOME/.local/share/icons/MacTahoe-dark" ;;
    wide-menu) [[ -n $(wide_menus) ]] ;;
    dock) [[ -d $PLUGINS_DIR/$DOCK_ID ]] ;;
    switcher) [[ -d $PLUGINS_DIR/$SWITCHER_ID ]] ;;
    osd) [[ -d $PLUGINS_DIR/$OSD_ID ]] ;;
    dictation-hud) [[ -d $PLUGINS_DIR/$HUD_ID ]] ;;
    menubar) [[ -d $PLUGINS_DIR/macos-theme.menubar ]] ;;
    bar-icons) [[ -d $PLUGINS_DIR/$BAR_ICONS_ID ]] ;;
    lock) [[ -n $(macos_locks) ]] ;;
    widgets) [[ -d $PLUGINS_DIR/$WIDGETS_ID ]] ;;
  esac
}

active() { [[ $(omarchy theme current 2>/dev/null) == "Macos" ]]; }

# Glass is the opacity look.lua gives every window, web-glass the one it gives
# browsers and web and Electron apps, snapping its SNAPPING switch, and blur
# its BLUR strength: each a
# line of look.lua, whose value is the second group of its pattern. The theme's
# own values are the defaults. Magnification is a key of the dock's section of
# shell.json, which the dock follows live.
LOOK_SETTINGS="glass web-glass snapping drop-follow blur title-bars traffic-lights"
declare -A LOOK_RULE=(
  [glass]='^(o\.window\("\.\*", \{ opacity = ")([0-9.]+) [0-9.]+'
  [web-glass]='^(o\.window\("\^\(brave-browser\|[^"]*", \{ opacity = ")([0-9.]+) [0-9.]+'
  [snapping]='^(local SNAPPING = )([01])'
  [drop-follow]='^(local DROP_FOLLOW = )([01])'
  [blur]='^(local BLUR = )([0-9]+)'
  [title-bars]='^(local TITLE_BARS = )([01])'
  [traffic-lights]='^(local LIGHTS = )([0-9]+)'
)
declare -A DEFAULT=([glass]=0.7 [web-glass]=1 [snapping]=1 [drop-follow]=1 [blur]=10 [title-bars]=1 [traffic-lights]=14 [magnification]=1.75)
look_get() {
  local v
  v=$(sed -nE "s/${LOOK_RULE[$1]}.*/\2/p" "$THEME_DIR/look.lua" 2>/dev/null) || true
  echo "${v:-${DEFAULT[$1]}}"
}
# look_set <setting> <value> [folder]: the theme folder, or another copy of it.
look_set() {
  local value="$2 $2" dir=${3:-$THEME_DIR}
  [[ $1 == glass || $1 == web-glass ]] || value=$2
  sed -i -E "s/${LOOK_RULE[$1]}/\1$value/" "$dir/look.lua"
  # The menu bar's panels and popups take the windows' glass too.
  [[ $1 == glass ]] && sed -i -E "/^\[popups\]/,/^\[/ s/^(background-alpha *= *).*/\1$2/" "$dir/shell.toml"
  return 0
}
magnification() {
  local m
  m=$(jq '.dock.magnification | numbers' "$SHELL_JSON" 2>/dev/null) || true
  echo "${m:-1.75}"
}
# Rewrites shell.json through jq: shell_write [jq options] <filter>. A missing
# one means Omarchy's defaults, as `omarchy dock` treats it. The new file goes
# beside the real one (a dotfiles symlink stays a symlink), keeps its mode, and
# takes its place in one rename.
# shortcut: a write by Omarchy (bar move, dock) between the read and the rename is lost; rare for one person, lock it if that changes.
shell_write() {
  local real src tmp
  mkdir -p "$(dirname "$SHELL_JSON")"
  real=$(readlink -f "$SHELL_JSON")
  src=$real
  [[ -s $src ]] || src="$OMARCHY_PATH/config/omarchy/shell.json"
  [[ -s $src ]] || src=/dev/null
  mkdir -p "$(dirname "$real")"
  tmp=$(mktemp "$real.XXXXXX")
  chmod --reference="$real" "$tmp" 2>/dev/null || chmod 644 "$tmp"
  if jq -S "$@" <(jq -s '.[0] // {}' "$src") >"$tmp"; then mv "$tmp" "$real"; else rm -f "$tmp"; return 1; fi
}
# Sets one value in shell.json: shell_set '.dock.magnification' 1.5.
shell_set() { shell_write --argjson v "$2" "$1 = \$v"; }
set_magnification() { shell_set '.dock.magnification' "$1"; }
dock_size() {
  local m
  m=$(jq '.dock.iconSize | numbers' "$SHELL_JSON" 2>/dev/null) || true
  echo "${m:-48}"
}

# Where a panel shows, volume or dictation: bottom (the middle) or top (right,
# under the bar); the panels follow shell.json's "hud" themselves.
hud_position() {
  [[ $(jq -r --arg k "$1" '.hud[$k] // empty' "$SHELL_JSON" 2>/dev/null) == top ]] && echo top || echo bottom
}

# Where the bar's clock sits: left, center (any of the middle sections) or
# right, as shell.json lays the bar out; right when it can't be told.
clock_position() {
  local section
  section=$(jq -r '.bar.layout // {} | to_entries[] | select((.value | type) == "array") | select(any(.value[]; .id? == "omarchy.clock")) | .key' "$SHELL_JSON" 2>/dev/null | head -n1)
  case $section in
    left) echo left ;;
    center*) echo center ;;
    *) echo right ;;
  esac
}
# Moves it: on the left after the workspaces, in the middle, or on the right
# after Control Center as macOS has it (or at the end of the right side).
set_clock() {
  case $1 in
    left) omarchy bar move omarchy.clock --section left >/dev/null ;;
    center) omarchy bar move omarchy.clock --section center >/dev/null ;;
    right)
      omarchy bar move omarchy.clock --after macos-theme.control-center >/dev/null 2>&1 ||
        omarchy bar move omarchy.clock --section right >/dev/null ;;
  esac
}

# The desktop widgets shown, as a JSON array: the known ids in shell.json's
# widgets.layout, or all of them when it has none, as the widgets do.
shown_widgets() {
  { cat "$SHELL_JSON" 2>/dev/null || true; } | jq -cs --arg all "$DESKTOP_WIDGETS" '($all | split(" ")) as $all
    | [(.[0].widgets.layout? // []) | arrays | .[] | .id? | strings | select(. as $id | $all | index($id))]
    | if length == 0 then $all else [$all[] as $id | select(index($id)) | $id] end' 2>/dev/null ||
    jq -cn --arg all "$DESKTOP_WIDGETS" '$all | split(" ")'
}
# Shows only the widgets named in $1 (comma-separated): the others leave
# shell.json, the ones kept stay where they are, and a new one gets no cell,
# so the widgets put it in the first free one.
set_shown_widgets() {
  shell_write --arg show "$1" '($show | split(",")) as $show
    | ([(.widgets.layout // []) | arrays | .[] | objects | select(.id as $id | $show | index($id))]) as $kept
    | .widgets.layout = $kept + [$show[] as $id | select([$kept[].id] | index($id) | not) | {id: $id}]'
}

# The bar's sections, in the order they sit on it.
BAR_SECTIONS="left centerBegin center centerEnd right tray"

# Every bar widget Omarchy knows, as {id: {name, enabled}}, without those an
# enabled copy stands in for (such as your own copy of the menu or the tray).
bar_widgets() {
  omarchy plugin list --json 2>/dev/null | jq -c --arg hide "$BAR_ICONS_ID" '
    [.[] | select((.kinds // []) | index("bar-widget"))] as $all
    | ([$all[] | select(.enabled and .clonedFrom != "") | .clonedFrom]) as $replaced
    | [$all[] | select((.id as $id | $replaced | index($id)) | not) | select(.id != $hide)]
    | map({key: .id, value: {name: .name, enabled: .enabled, drawer: (.id == "omarchy.tray" or .clonedFrom == "omarchy.tray")}}) | from_entries' 2>/dev/null || echo "{}"
}

# The bar as {sections: {left: [{id, name}], …}, hidden: [{id, name}]}.
bar_json() {
  local widgets layout
  widgets=$(bar_widgets)
  layout=$(jq -c '.bar.layout // {}' "$SHELL_JSON" 2>/dev/null || echo "{}")
  # With Control Center on the bar, the widgets it stands in for that sit in
  # the tray's drawer are unseen there and open from it alone, so they are
  # listed as hidden; showing one puts it on the bar, hiding it puts it back.
  jq -n --argjson w "$widgets" --argjson l "$layout" --arg order "$BAR_SECTIONS" --arg hide "$BAR_ICONS_ID" \
    --arg cc "macos-theme.control-center" --arg ccw "$CONTROL_CENTER_WIDGETS" '
    ($order | split(" ")) as $sections
    | ([$sections[] as $s | ($l[$s] // [])[] | .id? // empty]) as $placed
    | ([($l.tray // [])[] | .id? // empty]) as $inTray
    | ([(if ($placed | index($cc)) and $w[$cc].enabled then $ccw | split(" ") else [] end)[]
        | select(. as $id | $inTray | index($id)) | select($w[.].enabled)]) as $tucked
    | ([$hide] + $tucked) as $unlisted
    | {sections: ($sections | map({key: ., value: [($l[.] // [])[] | .id? // empty | select(. as $id | $unlisted | index($id) | not) | {id: ., name: ($w[.].name // .)} + (if $w[.].drawer then {drawer: true} else {} end)]}) | from_entries),
       hidden: ([$w | to_entries[] | select((.value.enabled | not) and (.key as $id | $placed | index($id) | not)) | {id: .key, name: .value.name}]
         + [$tucked[] | {id: ., name: $w[.].name}]) | sort_by(.name)}'
}

bar_text() {
  bar_json | jq -r '(.sections | to_entries[] | select(.value | length > 0) | "\(.key): \(.value | map(.name) | join(", "))"), (if (.hidden | length) > 0 then "hidden: \(.hidden | map(.name) | join(", "))" else empty end)'
}

# Shows, hides and orders the bar's items as $1 lays them out: hidden ones
# are turned off, then each section is filled in order, turning on what was
# off. Only known widgets and sections are taken. With Control Center on the
# bar, a hidden widget it stands in for goes to the tray's drawer instead of
# off, so its controls stay in Control Center.
apply_bar_layout() {
  local desired="$1" widgets id section i tuck=""
  widgets=$(bar_widgets)
  jq -e --arg order "$BAR_SECTIONS" --argjson w "$widgets" '
    (.sections // {}) as $s | (.hidden // []) as $h
    | ($s | type) == "object" and ($h | type) == "array"
    and ([$s | keys[]] - ($order | split(" ")) | length) == 0
    and ([$s[][], $h[]] | all(type == "string" and test("^[A-Za-z0-9._-]+$") and ($w[.] != null)))' \
    <<<"$desired" >/dev/null 2>&1 || { echo "Not a bar layout this bar can take" >&2; exit 1; }
  if jq -e '[.sections[][]?] | index("macos-theme.control-center")' <<<"$desired" >/dev/null; then
    tuck=" $CONTROL_CENTER_WIDGETS "
  fi
  while read -r id; do
    [[ -n $id ]] && [[ $tuck != *" $id "* ]] && [[ $(jq -r --arg id "$id" '.[$id].enabled' <<<"$widgets") == true ]] &&
      omarchy plugin disable "$id" >/dev/null
  done < <(jq -r '.hidden[]?' <<<"$desired")
  for section in $BAR_SECTIONS; do
    i=0
    while read -r id; do
      [[ -n $id ]] || continue
      if [[ $(jq -r --arg id "$id" '.[$id].enabled' <<<"$widgets") == true ]]; then
        omarchy bar move "$id" --section "$section" --index "$i" >/dev/null
      else
        omarchy plugin enable "$id" --section "$section" --index "$i" >/dev/null
      fi
      i=$((i + 1))
    done < <(jq -r --arg s "$section" '.sections[$s][]?' <<<"$desired")
  done
  while read -r id; do
    [[ -n $id ]] && [[ $tuck == *" $id "* ]] || continue
    if [[ $(jq -r --arg id "$id" '.[$id].enabled' <<<"$widgets") == true ]]; then
      omarchy bar move "$id" --section tray >/dev/null
    else
      omarchy plugin enable "$id" --section tray >/dev/null
    fi
  done < <(jq -r '.hidden[]?' <<<"$desired")
  say "Arranged the bar"
}

if $status; then
  if $json; then
    out=""
    for f in $FEATURES; do
      out+="$([[ -n $out ]] && echo ,)\"$f\":$(installed "$f" && echo true || echo false)"
    done
    set_out=""
    for k in $LOOK_SETTINGS; do set_out+="\"$k\":$(look_get "$k"),"; done
    printf '{"active":%s,"features":{%s},"settings":{%s"magnification":%s,"dock-size":%s},"clock":"%s","volume-hud":"%s","dictation-hud":"%s","widgets":%s,"icons-outside":%s}\n' \
      "$(active && echo true || echo false)" "$out" "$set_out" "$(magnification)" "$(dock_size)" "$(clock_position)" "$(hud_position volume)" "$(hud_position dictation)" "$(shown_widgets)" \
      "$( ! installed icons && [[ -d $HOME/.local/share/icons/MacTahoe-dark ]] && echo true || echo false)"
  else
    active && echo "The macOS theme is the current theme."
    for f in $FEATURES; do
      printf '%-14s %s\n' "$f" "$(installed "$f" && echo installed || echo "not installed")"
    done
    for k in $LOOK_SETTINGS; do printf '%-14s %s\n' "$k" "$(look_get "$k")"; done
    printf '%-14s %s\n' magnification "$(magnification)"
    printf '%-14s %s\n' dock-size "$(dock_size)"
    printf '%-14s %s\n' clock "$(clock_position)"
    printf '%-14s %s\n' volume-hud "$(hud_position volume)"
    printf '%-14s %s\n' dictation-hud "$(hud_position dictation)"
    printf '%-14s %s\n' widgets "$(shown_widgets | jq -r 'join(", ")')"
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

# give_back <omarchy id> [placement]: turns on again what stood where the theme's
# piece is, as it was before the theme: Omarchy's own, a clone of yours, or
# nothing if you had turned it off. Unrecorded (installed before the record
# was kept), Omarchy's own.
give_back() {
  local ids=$1 id
  [[ -s $BEFORE_THEME ]] && ids=$(jq -r --arg id "$1" '.[] | select(.id == $id or .clonedFrom == $id) | .id' "$BEFORE_THEME")
  for id in $ids; do omarchy plugin enable "$id" "${@:2}" >/dev/null 2>&1 || true; done
}

remove_osd() {
  omarchy plugin disable "$OSD_ID" >/dev/null 2>&1 || true
  give_back omarchy.osd
  rm -rf "${PLUGINS_DIR:?}/$OSD_ID"
  say "Removed the volume capsule and restored Omarchy's own"
}
remove_dock() {
  omarchy plugin disable "$DOCK_ID" >/dev/null 2>&1 || true
  give_back omarchy.dock
  rm -rf "${PLUGINS_DIR:?}/$DOCK_ID"
  say "Removed the macOS dock and restored Omarchy's own"
}
remove_wide_menu() {
  local dir
  for dir in $(wide_menus); do
    omarchy plugin disable "$(basename "$dir")" >/dev/null 2>&1 || true
    give_back omarchy.menu
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
  # The arrangement you made, for when the menu bar comes back.
  mkdir -p "$BACKUP_DIR"
  jq -e '.bar.layout | objects' "$SHELL_JSON" >"$BAR_REMEMBERED" 2>/dev/null || rm -f "$BAR_REMEMBERED"
  for id in $MENUBAR_IDS; do
    omarchy plugin disable "$id" >/dev/null 2>&1 || true
    rm -rf "${PLUGINS_DIR:?}/$id"
  done
  # Omarchy's workspaces back, after the menu button, in place of the
  # theme's clone (a clone of your own is left be).
  local dir drop=$MENUBAR_IDS
  for dir in $(workspaces_clones); do
    omarchy plugin disable "$(basename "$dir")" >/dev/null 2>&1 || true
    give_back omarchy.workspaces --section left --index 1
    drop+=" $(basename "$dir")"
    rm -rf "${dir:?}"
  done
  if [[ -s $BAR_BEFORE ]]; then
    # The bar as it was before the menu bar, with what other plugins have put
    # on it since; nothing of the menu bar's.
    if [[ $(cat "$BAR_BEFORE") == null ]]; then
      shell_write 'del(.bar.layout)'
    else
      shell_write --slurpfile was "$BAR_BEFORE" --arg drop "$drop" '($drop | split(" ")) as $drop
        | $was[0] as $was | ([$was[][]? | objects | .id]) as $known
        | .bar.layout = reduce ((.bar.layout // {}) | to_entries[]) as $s ($was;
            .[$s.key] = (.[$s.key] // []) + [$s.value[]? | objects
              | select(.id as $id | ($known | index($id) | not) and ($drop | index($id) | not))])'
    fi
    rm -f "$BAR_BEFORE"
    say "Removed the menu bar look and put the bar back as it was before it"
    return
  fi
  # Installed before the theme kept the bar's arrangement: Omarchy's default
  # bar, the clock in the middle, the system icons in a row after the tray.
  omarchy bar move omarchy.clock --section center >/dev/null 2>&1 || true
  omarchy bar move omarchy.tray --section right --index 0 >/dev/null 2>&1 || true
  for id in omarchy.keyboard-layout omarchy.agents omarchy.bluetooth omarchy.network omarchy.tailscale omarchy.audio omarchy.monitor omarchy.power; do
    omarchy bar move "$id" --after "$after" >/dev/null 2>&1 && after=$id
  done
  say "Removed the menu bar look and put the system widgets back on the bar"
}
remove_bar_icons() {
  omarchy plugin disable "$BAR_ICONS_ID" >/dev/null 2>&1 || true
  rm -rf "${PLUGINS_DIR:?}/$BAR_ICONS_ID"
  say "Removed the macOS bar icons; Omarchy's own are back"
}
remove_widgets() {
  omarchy plugin disable "$WIDGETS_ID" >/dev/null 2>&1 || true
  rm -rf "${PLUGINS_DIR:?}/$WIDGETS_ID"
  say "Removed the desktop widgets"
}
remove_lock() {
  local dir
  for dir in $(macos_locks); do
    omarchy plugin disable "$(basename "$dir")" >/dev/null 2>&1 || true
    give_back omarchy.lock
    rm -rf "${dir:?}"
  done
  # Omarchy's lock stays loaded on purpose, so only a restart hands it back the lock command.
  omarchy restart shell >/dev/null 2>&1 || true
  say "Removed the macOS lock screen and restored Omarchy's own"
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
  local t
  for t in "$HOME"/.local/share/icons/MacTahoe{,-light,-dark}; do
    theme_icons "$t" && rm -rf "${t:?}"
  done
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

# shellcheck source=backup.sh
source "$REPO/backup.sh"

# A preview shows the settings, and that is all: it edits only the copy of the
# theme Omarchy is showing, never the theme folder, so it needs no snapshot and
# the next theme refresh (or Apply) replaces it.
if $preview; then
  reload=false
  for k in "${!settings[@]}"; do
    case $k in
      # Blur changes in place, with nothing written: Apply writes it.
      blur)
        v=${settings[blur]}
        hyprctl eval "hl.config({ decoration = { blur = { enabled = $( ((v > 0)) && echo true || echo false ), size = $(( v > 0 ? v : 1 )) } } })" >/dev/null 2>&1 || true ;;
      glass|web-glass|snapping|drop-follow|title-bars|traffic-lights)
        installed theme || { echo "Install the theme first (--add theme), then set its $k." >&2; exit 1; }
        shown="$HOME/.local/state/omarchy/current/theme"
        active && [[ -f $shown/look.lua ]] || continue
        look_set "$k" "${settings[$k]}" "$shown"
        reload=true ;;
      # The dock shows these itself, with nothing written.
      magnification|dock-size) omarchy-shell -q omarchy.dock preview "$k" "${settings[$k]}" >/dev/null 2>&1 || true ;;
      *) echo "$k can't be previewed; set it instead" >&2; exit 1 ;;
    esac
  done
  if $reload; then hyprctl reload >/dev/null 2>&1 || true; fi
  exit 0
fi

case $mode in
  bar) if $json; then bar_json; else bar_text; fi; exit 0 ;;
  backups) if $json; then snapshot_list_json; else snapshot_list_text; fi; exit 0 ;;
  backup) say "Backed up as $(snapshot_take "Backed up by hand")"; exit 0 ;;
  restore) snapshot_restore "$mode_arg"; exit 0 ;;
  export) export_profile "$mode_arg"; exit 0 ;;
  import) import_profile "$mode_arg"; exit 0 ;;
esac

# Refused runs are refused before their snapshot, which would push out a real one.
if [[ -n $switch_to ]] && active; then
  omarchy theme list | grep -qxF "$switch_to" || { echo "No theme called $switch_to (see: omarchy theme list)" >&2; exit 1; }
fi
if [[ -n ${remove[theme]:-} && -z $switch_to ]] && active; then
  echo "Switch to another theme first (omarchy theme set <name>), then remove the theme again." >&2
  exit 1
fi

# Every change can be undone: a snapshot of how things are, first.
if (( ${#add[@]} + ${#remove[@]} + ${#settings[@]} )) || [[ -n $bar_layout$show_widgets ]]; then
  [[ -n ${MACOS_THEME_NO_SNAPSHOT:-} ]] || snapshot_take "$(describe_changes)" >/dev/null
fi

# The plugins that are on, recorded once: before the theme's first piece.
if (( ${#add[@]} )) && [[ ! -s $BEFORE_THEME ]]; then
  if none_installed; then
    mkdir -p "$BACKUP_DIR"
    omarchy plugin list --json 2>/dev/null |
      jq -ce '[.[] | select(.enabled) | {id, clonedFrom}]' >"$BEFORE_THEME" 2>/dev/null || rm -f "$BEFORE_THEME"
  fi
fi

if [[ -n $switch_to ]] && active; then
  omarchy theme set "$switch_to"
  say "Switched to $switch_to"
fi

if (( ${#remove[@]} )); then
  # Plugins before the theme they sit on.
  for f in widgets lock osd dock wide-menu switcher bar-icons menubar dictation-hud rows icons theme; do
    if [[ -n ${remove[$f]:-} ]] && installed "$f"; then "remove_${f//-/_}"; fi
  done
  say "Done. Backups of edited files end in .bak.$STAMP"
  # All of it gone: the next install records afresh what is on then.
  none_installed && rm -f "$BEFORE_THEME"
  if [[ -n ${remove[icons]:-} ]] && ! installed icons && [[ -d $HOME/.local/share/icons/MacTahoe-dark ]]; then
    echo "    MacTahoe icons weren't installed by the theme, so they stay in ~/.local/share/icons" >&2
  fi
  if [[ -z ${remove[icons]:-} ]] && installed icons && [[ -n ${remove[theme]:-} ]]; then
    echo "    MacTahoe icons are still installed. Remove them with: ./install.sh --remove icons" >&2
  fi
  (( ${#add[@]} + ${#settings[@]} )) || [[ -n $bar_layout ]] || exit 0
fi

want() { [[ -n ${add[$1]:-} ]]; }

# 1. The theme, as a local theme (so its .lua and ghostty.conf are kept).
if want theme; then
  declare -A kept_look=()
  # The settings and wallpapers come from the theme installed, or, when it
  # was removed, from the copy kept then: added again, it is as you left it.
  from=$THEME_DIR
  [[ -f $from/look.lua ]] || from=$(ls -dt "$BACKUP_DIR"/macos.*/ 2>/dev/null | head -n1) || true
  if [[ -n $from && -f $from/look.lua ]]; then
    for k in $LOOK_SETTINGS; do kept_look[$k]=$(THEME_DIR=$from look_get "$k"); done
  fi
  if [[ -d $THEME_DIR ]]; then
    keep_theme
    say "Backed up your existing macos theme to $kept"
    from=$kept
  fi
  mkdir -p "$THEME_DIR"
  cp -r "$REPO/theme/." "$THEME_DIR/"
  # Wallpapers and files you added stay; the theme's own files are the new ones.
  [[ -n $from && -d $from ]] && cp -rn "${from%/}/." "$THEME_DIR/"
  # So do the settings you chose.
  for k in "${!kept_look[@]}"; do look_set "$k" "${kept_look[$k]}"; done
  say "Installed the theme to $THEME_DIR"
fi

# 1b. MacTahoe icons (GPL-3.0, github.com/vinceliuice/MacTahoe-icon-theme):
# only the default color, into your home folder, no password needed.
if want icons && ! installed icons && [[ -d $HOME/.local/share/icons/MacTahoe-dark ]]; then
  say "MacTahoe icons are already installed, not by the theme; it uses them as they are"
elif want icons; then
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
      # Only icons with this mark are the theme's to remove.
      touch "$t/$OWN_MARK"
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
  # Installed already, this only updates the plugins: the bar stays exactly
  # as you arranged it, put back as it was once they are in.
  fresh=true; installed menubar && fresh=false
  kept_layout=
  $fresh || kept_layout=$(jq -ce '.bar.layout | objects' "$SHELL_JSON" 2>/dev/null) || true
  if $fresh; then
    mkdir -p "$BACKUP_DIR"
    jq -c '.bar.layout // null' "$SHELL_JSON" >"$BAR_BEFORE" 2>/dev/null || echo null >"$BAR_BEFORE"
  fi
  for id in $MENUBAR_IDS; do install_plugin "$id"; done
  # The workspaces: a click goes there, a right-click picks the layout, as a
  # macOS menu-bar item's menu does (Omarchy's cycles the shown one's layout
  # on a click). A clone of this Omarchy's widget, patched; none yet means
  # making one.
  ws_dir=$(theme_clone omarchy.workspaces Workspaces.qml "$WORKSPACES_MARK") || ws_dir=""
  if [[ -n $ws_dir && -f $ws_dir/Workspaces.qml ]]; then
    # This Omarchy's own widget each time, then patched: its updates come
    # along, and so does a newer patch.
    ws_src=$(omarchy-plugin-catalog 2>/dev/null | jq -r '.[] | select(.firstParty and .id == "omarchy.workspaces") | .sourceDir' | head -n1) || true
    [[ -n $ws_src && -f $ws_src/Workspaces.qml ]] && cp "$ws_src/Workspaces.qml" "$ws_dir/Workspaces.qml"
    cp "$REPO"/workspaces/{WorkspaceMenu.qml,LayoutIcon.qml,LayoutIcons.js} "$ws_dir/"
    perl -0pi "$REPO/workspaces-patch.pl" "$ws_dir/Workspaces.qml"
    grep -qF "$WORKSPACES_MARK" "$ws_dir/Workspaces.qml" ||
      echo "    Could not patch this Omarchy version's workspaces; a click on the shown one still cycles its layout." >&2
  else
    echo "    Could not clone Omarchy's workspaces; a click on the shown one still cycles its layout." >&2
  fi
  if [[ -n $kept_layout ]]; then
    # The arrangement as it was, the workspaces being this clone's.
    [[ -n $ws_dir ]] && kept_layout=$(jq -c --arg ws "$(basename "$ws_dir")" \
      'walk(if type == "object" and .id? == "omarchy.workspaces" then .id = $ws else . end)' <<<"$kept_layout")
    shell_set '.bar.layout' "$kept_layout"
  elif [[ -s $BAR_REMEMBERED ]] && layout=$(jq -ce 'objects' "$BAR_REMEMBERED" 2>/dev/null); then
    # Back after being removed: the arrangement it had then.
    shell_set '.bar.layout' "$layout"
    rm -f "$BAR_REMEMBERED"
    say "Put the bar back as you had arranged it"
  else
    # The first time, macOS's arrangement: the bold app name after the menu
    # button, Control Center by the clock, and the widgets it stands in for in
    # the tray drawer; Omarchy's other widgets as macOS keeps their like,
    # status in the middle, the input menu by Control Center, the bell past
    # the clock. Widgets from other plugins stay where their owner put them.
    omarchy bar put macos-theme.app-name --section left >/dev/null 2>&1 || true
    omarchy bar move macos-theme.app-name --before omarchy.workspaces >/dev/null 2>&1 || true
    omarchy bar move omarchy.clock --section right >/dev/null 2>&1 || true
    omarchy bar put macos-theme.control-center >/dev/null 2>&1 || true
    omarchy bar move macos-theme.control-center --before omarchy.clock >/dev/null 2>&1 || true
    for id in $CONTROL_CENTER_WIDGETS; do
      omarchy bar move "$id" --section tray >/dev/null 2>&1 || true
    done
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
  fi
  say "Installed the macOS menu bar (Inter, app name, Control Center, a shade for legibility)"
fi
[[ -n $(fc-list Inter) ]] || echo "    The theme uses the Inter font, which is not installed. Install it with: sudo pacman -S inter-font" >&2

if want wide-menu; then
  # Clone the menu of the Omarchy version installed here, then patch it (width,
  # magnifying glass, "Search"), so it matches this Omarchy's menu otherwise.
  menu_dir=$(theme_clone omarchy.menu Menu.qml "$WIDE_MARK") || menu_dir=""
  if [[ -n $menu_dir && -f $menu_dir/Menu.qml ]]; then
    perl -0pi "$REPO/menu-patch.pl" "$menu_dir/Menu.qml"
    grep -q "Style.space(560)), panel.width" "$menu_dir/Menu.qml" && say "Widened the Omarchy menu, with a Spotlight search line" || echo "    Could not patch this Omarchy version's menu; it keeps its own look." >&2
  else
    echo "    Could not clone Omarchy's menu; it keeps its own width." >&2
  fi
fi
if want bar-icons; then
  install_plugin "$BAR_ICONS_ID"
  omarchy bar put "$BAR_ICONS_ID" --section left >/dev/null 2>&1 || true
  say "Installed the macOS bar icons (Omarchy's Network, Bluetooth, Audio and Display widgets keep their updates)"
fi
if want widgets; then
  install_plugin "$WIDGETS_ID"
  say "Installed the desktop widgets (top left: clock, calendar, weather, now playing)"
fi
if want lock; then
  # Clone Omarchy's lock (only a clone may unlock), take this Omarchy's own
  # locking and PAM code into it every time, and draw it with the macOS view.
  lock_src="$OMARCHY_PATH/shell/plugins/lock"
  lock_dir=$(theme_clone omarchy.lock LockView.qml "$LOCK_MARK") || lock_dir=""
  if [[ -n $lock_dir ]]; then
    for f in "$lock_src"/*; do [[ -e $f && ${f##*/} != manifest.json ]] && cp -r "$f" "$lock_dir/"; done
    cp "$REPO/lock/LockView.qml" "$lock_dir/LockView.qml"
    omarchy plugin enable "$(basename "$lock_dir")" >/dev/null 2>&1 || true
    # The shell caches loaded QML, and Omarchy's lock keeps the lock command
    # until a restart; the refresh below restarts it when the theme is current.
    active || omarchy restart shell >/dev/null 2>&1 || true
    say "Installed the macOS lock screen (see it without locking: omarchy-shell lock preview)"
  else
    echo "    Could not clone Omarchy's lock screen; it keeps its own look." >&2
  fi
fi
if want dictation-hud; then
  # The Voxtype tips once, when the HUD is new, not on every reinstall (each Update).
  hud_fresh=true; installed dictation-hud && hud_fresh=false
  install_plugin "$HUD_ID"
  say "Installed the dictation HUD"
  if $hud_fresh; then
    if command -v voxtype >/dev/null; then
      echo "    Voxtype draws its own overlay too. To show only the HUD, run:" >&2
      echo "      voxtype config set osd.enabled false && systemctl --user restart voxtype" >&2
    else
      echo "    Voxtype isn't installed; the HUD stays hidden until it is." >&2
    fi
  fi
fi

# 4b. Settings.
look_changed=false
for k in $LOOK_SETTINGS; do
  [[ -n ${settings[$k]:-} ]] || continue
  installed theme || { echo "Install the theme first (--add theme), then set its $k." >&2; exit 1; }
  look_set "$k" "${settings[$k]}"
  look_changed=true
  say "Set $k to ${settings[$k]}"
done
if [[ -n ${settings[magnification]:-} ]]; then
  set_magnification "${settings[magnification]}"
  say "Set the dock's magnification to ${settings[magnification]}"
fi
if [[ -n ${settings[dock-size]:-} ]]; then
  shell_set '.dock.iconSize' "${settings[dock-size]}"
  say "Set the dock's icons to ${settings[dock-size]} points"
fi
# The bar follows shell.json itself, so its items move without a reload.
[[ -n $bar_layout ]] && apply_bar_layout "$bar_layout"
if [[ -n ${settings[clock]:-} ]]; then
  set_clock "${settings[clock]}"
  say "Moved the clock to the ${settings[clock]} of the bar"
fi
for k in volume dictation; do
  [[ -n ${settings[$k-hud]:-} ]] || continue
  shell_set ".hud.$k" "\"${settings[$k-hud]}\""
  say "The $k panel now shows at the ${settings[$k-hud]}"
done
# The widgets follow shell.json themselves too.
if [[ -n $show_widgets ]]; then
  set_shown_widgets "$show_widgets"
  say "Showing the desktop widgets: ${show_widgets//,/, }"
fi

# 5. Apply: refresh the active theme in place, or switch to it when it was asked for.
# The dock follows shell.json itself, so its magnification and size need no refresh.
if active && { (( ${#add[@]} )) || $look_changed; }; then
  refresh
elif want theme; then
  omarchy theme set macos
fi
say "Done. The bar, menus and popups pick up the theme now; restart the shell if they don't: omarchy restart shell"
