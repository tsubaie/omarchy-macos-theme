#!/usr/bin/perl -0pi
# Patches a clone of Omarchy's workspaces bar widget (Workspaces.qml) so a
# click goes to a workspace, and a click on the shown one, or a right-click on
# any, opens a menu of its layouts (WorkspaceMenu.qml, copied next to it),
# instead of a click on the shown workspace cycling its layout. Each change is skipped when already
# applied, so it is safe to re-run.
# Usage: perl -0pi workspaces-patch.pl path/to/Workspaces.qml

unless (/macOS theme: a click goes to a workspace/) {
  s/(\n( +)WidgetButton \{\n)/$1$2  id: workspaceButton\n/;
  s/( +)onPressed: function\(\) \{\n +if \(shown\) root\.cycleLayout\(\)\n +else root\.focusWorkspace\(modelData\)\n +\}/
    "$1\/\/ macOS theme: a click goes to a workspace; a click on the one shown, or a\n" .
    "$1\/\/ right-click on any, opens its layout menu (Super + L still cycles it).\n" .
    "$1onPressed: function(button) {\n" .
    "$1  if (button === Qt.RightButton || shown) modesMenu.show(workspaceButton, modelData, slot)\n" .
    "$1  else root.focusWorkspace(modelData)\n" .
    "$1}"/e;
  s/(\n\}\s*)\z/\n\n  \/\/ macOS theme: the layout menu a right-click on a workspace opens.\n  WorkspaceMenu {\n    id: modesMenu\n    bar: root.bar\n  }$1/;
}

# The shown workspace: its layout as a map of its windows (LayoutIcon.qml,
# copied next to it) rather than the font's square, circle and triangle, lit
# as macOS lights an open menu-bar item, on a soft pill. The pill is the icon
# with the same room on each side, both placed from one rounded point, so the
# icon sits exactly in its middle at any display scale.
unless (/LayoutIcon \{/) {
  s/(\n( +)id: workspaceButton\n)/$1$2labelVisible: !shown\n$2\/\/ macOS theme: the shown workspace lit, its layout's icon on a pill.\n$2Rectangle {\n$2  id: layoutPill\n$2  readonly property int icon: Math.round(Style.bar.iconCanvas * 0.85)\n$2  readonly property int padX: Math.round(icon * 0.45)\n$2  readonly property int padY: Math.round(icon * 0.2)\n$2  visible: workspaceButton.shown\n$2  z: -1\n$2  width: icon + padX * 2\n$2  height: icon + padY * 2\n$2  x: Math.round((workspaceButton.width - width) \/ 2)\n$2  y: Math.round((workspaceButton.height - height) \/ 2)\n$2  radius: height \/ 2\n$2  color: Qt.rgba(1, 1, 1, 0.22)\n$2}\n$2LayoutIcon {\n$2  visible: workspaceButton.shown\n$2  x: layoutPill.x + layoutPill.padX\n$2  y: layoutPill.y + layoutPill.padY\n$2  size: layoutPill.icon\n$2  mode: root.activeMode\n$2  color: workspaceButton.foreground\n$2}\n/;
}

# The shown workspace's button as wide as its pill, with 4 px each side, so the
# pill never spills onto the widget beside it (the logo's open pill).
unless (/macOS theme: room for the pill/) {
  s/\n( +)fixedWidth: root\.vertical \? root\.barSize : Style\.space\(20\)\n/\n$1\/\/ macOS theme: room for the pill.\n$1fixedWidth: root.vertical ? root.barSize : (shown ? Math.max(Style.space(20), layoutPill.width + Style.space(8)) : Style.space(20))\n/;
}
