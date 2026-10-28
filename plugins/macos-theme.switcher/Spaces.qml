import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// Super+Tab workspace switcher, in the same glass as the app switcher. Each
// workspace with windows is a miniature: the wallpaper with every window drawn
// live at its place. Tab / Shift+Tab move while Super is held, letting go of
// Super switches, Esc cancels.
Item {
  id: root

  property bool opened: false
  property var spaces: []
  property int index: 0
  property bool commitWhenLoaded: false
  property int pendingStep: 1
  property var collect: []
  property string wallpaper: ""
  // Workspaces in the order they were last visited, newest first.
  property var visited: []

  Connections {
    target: Hyprland
    function onFocusedWorkspaceChanged() {
      var ws = Hyprland.focusedWorkspace
      if (!ws || !(ws.id > 0)) return
      root.visited = [ws.id].concat(root.visited.filter(function(id) { return id !== ws.id })).slice(0, 50)
    }
  }

  // Large miniatures, shrunk only as far as needed to fit the screen.
  property int screenWidth: 1920
  readonly property int thumbWidth: Math.max(Math.round(200 * Style.fontScale),
    Math.min(Math.round(420 * Style.fontScale),
      Math.floor((screenWidth - Style.space(160) - Math.max(0, spaces.length - 1) * Style.space(22)) / Math.max(1, spaces.length) - Style.space(12))))

  ShellIpc {
    target: "macos-spaces"
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
      root.spaces = []
      root.collect = []
      spacesQuery.running = true
      return
    }
    if (root.spaces.length > 0) root.index = (root.index + direction + root.spaces.length) % root.spaces.length
  }

  function commit() {
    if (!root.opened) return
    if (spacesQuery.running) { root.commitWhenLoaded = true; return }
    var space = root.spaces[root.index]
    root.close()
    if (space) Util.execDetached("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + space.id + "\" })"))
  }

  function close() {
    root.opened = false
    root.commitWhenLoaded = false
  }

  // The live window behind a Hyprland address, for the screen copy.
  function toplevelFor(address) {
    var want = String(address || "").replace(/^0x/, "")
    var values = Hyprland.toplevels.values
    for (var i = 0; i < values.length; i++) {
      if (String(values[i].address || "").replace(/^0x/, "") === want) return values[i].wayland
    }
    return null
  }

  // One line each: clients, monitors, the active workspace, the wallpaper.
  function load(text) {
    var parts = text.split("\n@@\n")
    var clients = [], monitors = [], active = {}
    try { clients = JSON.parse(parts[0]) } catch (e) {}
    try { monitors = JSON.parse(parts[1]) } catch (e) {}
    try { active = JSON.parse(parts[2]) } catch (e) {}
    root.wallpaper = String(parts[3] || "").trim()

    var monitorById = {}
    monitors.forEach(function(m) { monitorById[m.id] = m })
    var byId = {}
    var out = []
    clients.forEach(function(c) {
      var ws = c.workspace || {}
      if (!c.mapped || !(ws.id > 0)) return
      var space = byId[ws.id]
      if (!space) {
        var m = monitorById[c.monitor] || monitors[0] || { x: 0, y: 0, width: 1920, height: 1080 }
        space = byId[ws.id] = { id: ws.id, name: String(ws.name || ws.id), monitor: m, windows: [] }
        out.push(space)
      }
      space.windows.push({ address: c.address, x: c.at[0], y: c.at[1], w: c.size[0], h: c.size[1], floating: c.floating })
      // A workspace is as recent as its most recently focused window.
      var rank = typeof c.focusHistoryID === "number" ? c.focusHistoryID : 9999
      space.rank = Math.min(space.rank === undefined ? 9999 : space.rank, rank)
    })
    // Tiled windows first, floating ones on top, as on screen.
    out.forEach(function(s) { s.windows.sort(function(a, b) { return (a.floating ? 1 : 0) - (b.floating ? 1 : 0) }) })
    // Most recently used first, the current workspace leading, so a quick
    // Super+Tab toggles between the last two workspaces, like Alt+Tab does
    // between apps.
    out.forEach(function(s) {
      var seen = root.visited.indexOf(s.id)
      // Visited workspaces first, in visit order; then the rest by window focus.
      s.order = s.id === active.id ? -1 : (seen >= 0 ? seen : 1000 + s.rank)
    })
    out.sort(function(a, b) { return a.order - b.order })
    root.spaces = out

    if (out.length === 0) { root.close(); return }
    if (root.pendingStep < 0) root.index = out.length - 1
    else root.index = out.length > 1 ? 1 : 0
    if (root.commitWhenLoaded) root.commit()
  }

  Process {
    id: spacesQuery
    command: ["sh", "-c", "hyprctl clients -j; echo; echo @@; hyprctl monitors -j; echo; echo @@; hyprctl activeworkspace -j; echo; echo @@; readlink -f \"$HOME/.local/state/omarchy/current/background\""]
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(data) { root.collect.push(data) }
    }
    onExited: root.load(root.collect.join(""))
  }

  OverlayWindow {
    id: spacesWindow
    shown: root.opened && root.spaces.length > 0
    onWidthChanged: if (width > 0) root.screenWidth = width
    WlrLayershell.namespace: "omarchy-switcher"
    onContentRevealedChanged: if (contentRevealed) keys.forceActiveFocus()

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
      // Letting go of Super switches.
      Keys.onReleased: function(event) {
        if (event.key === Qt.Key_Super_L || event.key === Qt.Key_Super_R || event.key === Qt.Key_Meta) {
          root.commit()
          event.accepted = true
        }
      }
    }

    Rectangle {
      id: card
      readonly property int pad: Style.space(26)
      anchors.centerIn: parent
      width: Math.min(parent.width - Style.space(80), row.width + pad * 2)
      height: row.height + pad * 2
      radius: Style.space(30)
      color: Qt.rgba(0.2, 0.2, 0.23, 0.34)
      clip: true

      MouseArea { anchors.fill: parent }

      Row {
        id: row
        anchors.centerIn: parent
        spacing: Style.space(22)

        Repeater {
          model: root.opened ? root.spaces : []

          delegate: Item {
            id: spaceItem
            required property var modelData
            required property int index
            readonly property bool selected: spaceItem.index === root.index
            // A taller box than an ultrawide screen's shape: the wallpaper fills
            // it and the windows sit centered at their true proportions.
            readonly property int thumbHeight: Math.round(root.thumbWidth * 0.56)
            readonly property real scaleFactor: Math.min(root.thumbWidth / Math.max(1, modelData.monitor.width), thumbHeight / Math.max(1, modelData.monitor.height))
            readonly property real offsetX: (root.thumbWidth - modelData.monitor.width * scaleFactor) / 2
            readonly property real offsetY: (thumbHeight - modelData.monitor.height * scaleFactor) / 2

            width: root.thumbWidth + Style.space(12)
            height: thumbHeight + Style.space(12) + label.height + Style.space(8)

            // The selection ring around the chosen workspace.
            Rectangle {
              width: root.thumbWidth + Style.space(12)
              height: spaceItem.thumbHeight + Style.space(12)
              radius: Style.space(16)
              color: spaceItem.selected ? Qt.rgba(0, 0, 0, 0.28) : "transparent"
              border.width: spaceItem.selected ? 2 : 0
              border.color: "#0a84ff"
            }

            // The miniature: wallpaper, then each window live at its place.
            Item {
              x: Style.space(6)
              y: Style.space(6)
              width: root.thumbWidth
              height: spaceItem.thumbHeight
              clip: true

              Image {
                anchors.fill: parent
                source: root.wallpaper ? "file://" + root.wallpaper : ""
                sourceSize: Qt.size(root.thumbWidth * 2, spaceItem.thumbHeight * 2)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                smooth: true
              }

              Repeater {
                model: spaceItem.modelData.windows

                delegate: Item {
                  required property var modelData
                  x: Math.round(spaceItem.offsetX + (modelData.x - spaceItem.modelData.monitor.x) * spaceItem.scaleFactor)
                  y: Math.round(spaceItem.offsetY + (modelData.y - spaceItem.modelData.monitor.y) * spaceItem.scaleFactor)
                  width: Math.max(4, Math.round(modelData.w * spaceItem.scaleFactor))
                  height: Math.max(4, Math.round(modelData.h * spaceItem.scaleFactor))

                  Rectangle {
                    anchors.fill: parent
                    radius: Style.space(3)
                    color: Qt.rgba(0.11, 0.11, 0.12, 0.85)
                  }

                  ScreencopyView {
                    anchors.fill: parent
                    captureSource: root.opened ? root.toplevelFor(parent.modelData.address) : null
                    live: root.opened
                    constraintSize: Qt.size(width * 2, height * 2)
                    smooth: true
                  }
                }
              }
            }

            Text {
              id: label
              anchors.horizontalCenter: parent.horizontalCenter
              y: spaceItem.thumbHeight + Style.space(18)
              textFormat: Text.PlainText
              text: "Workspace " + spaceItem.modelData.name
              color: spaceItem.selected ? "#ffffff" : Qt.rgba(1, 1, 1, 0.6)
              font.family: "Adwaita Sans"
              font.pixelSize: Math.round(13 * Style.fontScale)
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onEntered: root.index = spaceItem.index
              onClicked: { root.index = spaceItem.index; root.commit() }
            }
          }
        }
      }
    }
  }
}
