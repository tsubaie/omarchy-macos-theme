import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// macOS-style app switcher. Alt+Tab opens it on the next most recent app;
// Tab / Shift+Tab move while Alt is held, releasing Alt switches, Esc cancels.
// It lists every running app across all workspaces, most recent first, and
// switching to one goes to the workspace its window is on.
Item {
  id: root

  property bool opened: false
  property var apps: []
  property int index: 0
  // Releasing Alt can come before the window list has loaded.
  property bool commitWhenLoaded: false
  property int pendingStep: 1
  property var collect: []

  readonly property int tile: Math.round(104 * Style.fontScale)
  readonly property int iconSize: Math.round(80 * Style.fontScale)

  ShellIpc {
    target: "macos-switcher"
    function next(): string { root.step(1); return "ok" }
    function prev(): string { root.step(-1); return "ok" }
    function commit(): string { root.commit(); return "ok" }
    function cancel(): string { root.close(); return "ok" }
  }

  function step(direction) {
    if (!root.opened) {
      root.opened = true
      root.commitWhenLoaded = false
      root.pendingStep = direction
      root.apps = []
      root.collect = []
      clients.running = true
      return
    }
    if (root.apps.length > 0) root.index = (root.index + direction + root.apps.length) % root.apps.length
  }

  function commit() {
    if (!root.opened) return
    if (clients.running) { root.commitWhenLoaded = true; return }
    var app = root.apps[root.index]
    root.close()
    if (app) root.activate(app)
  }

  function close() {
    root.opened = false
    root.commitWhenLoaded = false
  }

  // A window without an app id may name its app at the end of its title.
  function entryForTitle(title) {
    title = String(title || "")
    var best = null
    var values = DesktopEntries.applications.values
    for (var i = 0; i < values.length; i++) {
      var name = String(values[i].name || "")
      if (name.length < 3 || values[i].noDisplay) continue
      var at = title.length - name.length
      var bounded = at === 0 || /[\s\-—–|:·]/.test(title.charAt(at - 1))
      if (at >= 0 && title.substr(at) === name && bounded && (!best || name.length > best.name.length)) best = values[i]
    }
    return best
  }

  // One entry per app, ordered by its most recently focused window.
  function load(json) {
    var list = []
    try { list = JSON.parse(json) } catch (e) { list = [] }
    var byKey = {}
    var out = []
    for (var i = 0; i < list.length; i++) {
      var c = list[i]
      var ws = c.workspace || {}
      var minimized = ws.name === "special:minimized"
      // Other special workspaces (scratchpad, console) are not apps you switch to.
      if (!c.mapped || (ws.id <= 0 && !minimized)) continue
      var cls = String(c.class || "")
      var entry = cls ? DesktopEntries.heuristicLookup(cls) : root.entryForTitle(c.title)
      var key = entry ? entry.id : (cls || "window:" + c.address)
      var rank = typeof c.focusHistoryID === "number" ? c.focusHistoryID : 9999
      var app = byKey[key]
      if (!app) {
        app = byKey[key] = {
          key: key,
          name: entry ? String(entry.name || "") : (cls || String(c.title || "")),
          icon: Quickshell.iconPath(entry && entry.icon ? entry.icon : cls, true) || Quickshell.iconPath("application-x-executable", true),
          rank: rank,
          address: c.address,
          minimized: minimized
        }
        out.push(app)
      } else if (rank < app.rank) {
        app.rank = rank
        app.address = c.address
        app.minimized = minimized
      }
    }
    out.sort(function(a, b) { return a.rank - b.rank })
    root.apps = out
    // Like macOS, the first press lands on the previous app.
    if (out.length === 0) root.index = 0
    else if (root.pendingStep < 0) root.index = out.length - 1
    else root.index = out.length > 1 ? 1 : 0
    if (out.length === 0) root.close()
    else if (root.commitWhenLoaded) root.commit()
  }

  function activate(app) {
    var target = "window = \"address:" + app.address + "\""
    var steps = []
    if (app.minimized) {
      // Back from the dock onto the workspace in front of the user.
      steps.push("hl.dsp.window.move({ workspace = \"e+0\", " + target + " })")
    }
    steps.push("hl.dsp.focus({ " + target + " })")
    steps.push("hl.dsp.window.alter_zorder({ mode = \"top\", " + target + " })")
    Util.execDetached(steps.map(function(s) { return "hyprctl dispatch " + Util.shellQuote(s) }).join(" && "))
  }

  Process {
    id: clients
    command: ["hyprctl", "clients", "-j"]
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(data) { root.collect.push(data) }
    }
    onExited: root.load(root.collect.join(""))
  }

  OverlayWindow {
    id: panelWindow
    shown: root.opened && root.apps.length > 0
    WlrLayershell.namespace: "omarchy-switcher"
    onContentRevealedChanged: if (contentRevealed) keys.forceActiveFocus()

    // Clicking off the switcher cancels it.
    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    Item {
      id: keys
      anchors.fill: parent
      focus: true
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Tab || event.key === Qt.Key_Right) root.step(1)
        else if (event.key === Qt.Key_Backtab || event.key === Qt.Key_Left) root.step(-1)
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.commit()
        else if (event.key === Qt.Key_Escape) root.close()
        else return
        event.accepted = true
      }
      // Letting go of Alt switches, as letting go of Cmd does on macOS.
      Keys.onReleased: function(event) {
        if (event.key === Qt.Key_Alt || event.key === Qt.Key_AltGr || event.key === Qt.Key_Meta) {
          root.commit()
          event.accepted = true
        }
      }
    }

    // Like the macOS switcher: a borderless sheet of tinted glass (Hyprland
    // blurs what is behind it), with the same padding above and below the
    // icons; the selected app's name sits in the bottom padding.
    Rectangle {
      id: card
      readonly property int pad: Math.round(root.tile * 0.36)
      anchors.centerIn: parent
      width: row.width + pad * 2
      height: row.height + pad * 2
      radius: Style.space(30)
      color: Qt.rgba(0.2, 0.2, 0.23, 0.34)

      // Swallow clicks on the card so they do not cancel.
      MouseArea { anchors.fill: parent }

      Row {
        id: row
        anchors.centerIn: parent

        Repeater {
          model: root.apps

          delegate: Item {
            id: tileItem
            required property var modelData
            required property int index
            readonly property bool selected: tileItem.index === root.index

            width: root.tile
            height: root.tile

            // The selected app sits on a darker rounded square, as on macOS.
            Rectangle {
              visible: tileItem.selected
              width: root.tile
              height: root.tile
              radius: Style.space(16)
              color: Qt.rgba(0, 0, 0, 0.28)
            }

            Image {
              x: (root.tile - root.iconSize) / 2
              y: (root.tile - root.iconSize) / 2
              width: root.iconSize
              height: root.iconSize
              sourceSize: Qt.size(root.iconSize * 2, root.iconSize * 2)
              source: tileItem.modelData.icon
              fillMode: Image.PreserveAspectFit
              smooth: true
              mipmap: true
              asynchronous: true
            }

            Text {
              id: nameText
              y: root.tile + Style.space(6)
              width: root.tile
              horizontalAlignment: Text.AlignHCenter
              textFormat: Text.PlainText
              text: tileItem.modelData.name
              visible: tileItem.selected
              elide: Text.ElideRight
              color: Qt.rgba(1, 1, 1, 0.85)
              font.family: "Adwaita Sans"
              font.pixelSize: Math.round(13 * Style.fontScale)
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onEntered: root.index = tileItem.index
              onClicked: { root.index = tileItem.index; root.commit() }
            }
          }
        }
      }
    }
  }
}
