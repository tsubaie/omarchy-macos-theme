import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// The workspaces a dragged window can be dropped onto, as on macOS: drag a
// window to the middle of the top edge and they slide down in a strip, with a
// "+" for a new one; nearing the top, a faint outline shows the spot. Hyprland
// holds the pointer while a window is dragged, so this never sees it:
// look.lua's snapping follows the drag and drives it.
//   omarchy-shell -q macos-drop-spaces hint <monitor>     the outline of the spot
//   omarchy-shell -q macos-drop-spaces open <monitor>
//   omarchy-shell -q macos-drop-spaces hover <x>          (x on that screen)
//   omarchy-shell -q macos-drop-spaces drop <address> <x> <follow>  moves the window
//                                 there, and with follow true goes there too
//   omarchy-shell -q macos-drop-spaces close
Item {
  id: root

  property bool opened: false
  property bool shown: false
  // Only the faint outline of the spot, while a drag nears the top.
  property bool hinting: false
  property string monitorName: ""
  property var spaces: []
  property int activeSpace: 0
  // The highest workspace number on any screen: "+" makes the one after it.
  property int lastSpace: 0
  property string wallpaper: ""
  property var collect: []
  // The tile under the pointer: a workspace's index, spaces.length for "+", or -1.
  property int target: -1
  // The shell's API (from Switcher.qml): how far a top bar reaches down.
  property var shell: null

  ShellIpc {
    target: "macos-drop-spaces"
    function hint(monitor: string): string { if (!root.opened) root.hinting = true; return "ok" }
    function open(monitor: string): string { root.open(monitor); return "ok" }
    function hover(x: real): string { root.target = root.tileAt(x); return "ok" }
    function drop(address: string, x: real, follow: bool): string { root.drop(address, x, follow); return "ok" }
    function close(): string { root.close(); return "ok" }
  }

  function open(monitor) {
    if (root.opened) return
    root.opened = true
    root.hinting = false
    root.monitorName = monitor
    root.target = -1
    root.collect = []
    query.running = true
  }

  function close() {
    root.opened = false
    root.hinting = false
    root.shown = false
    root.target = -1
  }

  // The tile at x on the screen, from the strip's own layout.
  function tileAt(x) {
    for (var i = 0; i < tiles.count; i++) {
      var tile = tiles.itemAt(i)
      if (!tile) continue
      var left = strip.x + tile.x - strip.spacing / 2
      if (x >= left && x < left + tile.width + strip.spacing) return i
    }
    return -1
  }

  function drop(address, x, follow) {
    var i = root.tileAt(x)
    var space = i >= 0 && i < root.spaces.length ? root.spaces[i] : null
    // "+" is a new workspace, numbered after every one there is: not one of
    // the pinned ones that happens to be empty. Hyprland removes it again
    // once its last window leaves, as it does any workspace not pinned.
    var where = space ? String(space.id) : (i === root.spaces.length ? String(root.lastSpace + 1) : "")
    root.close()
    if (!where || !address || (space && space.id === root.activeSpace)) return
    var command = "hyprctl dispatch " + Util.shellQuote(
      "hl.dsp.window.move({ workspace = \"" + where + "\", follow = " + (follow ? "true" : "false") + ", window = \"address:" + address + "\" })")
    // A new workspace would open on whichever screen Omarchy gives that
    // number to; it belongs on the screen the window was dropped on.
    if (!space) command += " && hyprctl dispatch " + Util.shellQuote(
      "hl.dsp.workspace.move({ workspace = \"" + where + "\", monitor = \"" + root.monitorName + "\" })")
    Util.execDetached(command)
  }

  function load(text) {
    if (!root.opened) return
    var parts = text.split("\n@@\n")
    var clients = [], monitors = [], workspaces = []
    try { clients = JSON.parse(parts[0]) } catch (e) {}
    try { monitors = JSON.parse(parts[1]) } catch (e) {}
    try { workspaces = JSON.parse(parts[2]) } catch (e) {}
    root.wallpaper = String(parts[3] || "").trim()
    var monitor = monitors.filter(function(m) { return m.name === root.monitorName })[0]
    if (!monitor) { root.close(); return }
    var seen = function(c) { return c.mapped && !c.hidden && c.workspace && c.workspace.id > 0 }
    root.activeSpace = monitor.activeWorkspace ? monitor.activeWorkspace.id : 0
    root.lastSpace = workspaces.reduce(function(last, w) { return Math.max(last, w.id) }, 0)
    root.spaces = workspaces.filter(function(w) { return w.id > 0 && w.monitorID === monitor.id })
      .sort(function(a, b) { return a.id - b.id })
      .map(function(w) {
        return { id: w.id, name: String(w.name || w.id),
                 windows: clients.filter(function(c) { return seen(c) && c.workspace.id === w.id }).map(function(c) {
                   return { address: c.address, x: c.at[0] - monitor.x, y: c.at[1] - monitor.y, w: c.size[0], h: c.size[1] }
                 }) }
      })
    root.shown = true
  }

  Process {
    id: query
    command: ["sh", "-c", "hyprctl clients -j; echo; echo @@; hyprctl monitors -j; echo; echo @@; hyprctl workspaces -j; echo; echo @@; readlink -f \"$HOME/.local/state/omarchy/current/background\""]
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(data) { root.collect.push(data) }
    }
    onExited: root.load(root.collect.join(""))
  }

  OverlayWindow {
    id: overlay
    shown: root.shown || root.hinting
    shownKeyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "omarchy-drop-spaces"
    // Shows only; the drag keeps the pointer.
    mask: Region {}

    readonly property real thumbHeight: Math.round(height * 0.11)
    // Hung just below a top bar, where the drag is held.
    readonly property int barClear: root.shell && root.shell.bar && !root.shell.bar.barHidden && root.shell.bar.position === "top"
      ? root.shell.bar.barSizeFor(screen ? screen.name : "") : 0
    readonly property bool live: overlay.contentRevealed

    // The spot, faintly: the top edge's middle fifth, where a drag opens the strip.
    Rectangle {
      visible: root.hinting && !root.shown
      anchors.horizontalCenter: parent.horizontalCenter
      y: overlay.barClear + Style.space(8)
      width: Math.round(overlay.width * 0.2)
      height: Style.space(40)
      radius: height / 2
      color: Qt.rgba(1, 1, 1, 0.08)
      border.width: 1
      border.color: Qt.rgba(1, 1, 1, 0.35)
      opacity: overlay.live ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: Style.duration(160) } }
      Text {
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: "Move to another desktop"
        color: Qt.rgba(1, 1, 1, 0.85)
        font.family: "Inter"
        font.pixelSize: Math.round(12 * Style.fontScale)
      }
    }

    // A glass shelf the strip sits on, sliding down from the top.
    Rectangle {
      id: shelf
      x: strip.x - Style.space(18)
      width: strip.width + Style.space(36)
      height: strip.height + Style.space(28)
      y: overlay.live ? overlay.barClear + Style.space(8) : -height
      radius: Style.space(20)
      color: Qt.rgba(0.11, 0.11, 0.12, 0.72)
      Behavior on y { NumberAnimation { duration: Style.duration(220); easing.type: Easing.OutCubic } }
    }

    Row {
      id: strip
      anchors.horizontalCenter: parent.horizontalCenter
      y: shelf.y + Style.space(14)
      spacing: Style.space(18)

      Repeater {
        id: tiles
        model: root.shown ? root.spaces.concat([{ id: 0, name: "", windows: [], add: true }]) : []
        delegate: SpaceMini {
          required property var modelData
          required property int index
          space: modelData
          add: !!modelData.add
          wallpaper: root.wallpaper
          screenWidth: overlay.width
          screenHeight: overlay.height
          thumbHeight: overlay.thumbHeight
          live: overlay.live
          ringed: index === root.target
          hovered: !modelData.add && modelData.id === root.activeSpace
        }
      }
    }
  }
}
