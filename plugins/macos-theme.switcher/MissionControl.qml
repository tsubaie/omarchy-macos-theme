import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Commons
import qs.Ui
import "MissionLayout.js" as MissionLayout

// Mission Control, as macOS has it (Ctrl+Up): the current workspace's windows
// fly from where they are into a spread over the dimmed wallpaper, and the
// screen's workspaces sit in a strip along the top. Hovering a window shows
// its title; clicking it brings it forward, clicking a workspace goes there.
// Ctrl+Up again, Esc or a click on the wallpaper closes it, the windows
// flying back.
Item {
  id: root

  property bool opened: false
  // 0 with every window where it is on screen, 1 spread out.
  property real spreadOut: 0
  property var windows: []
  property var spaces: []
  property int activeSpace: 0
  // The highest workspace number on any screen: "+" makes the one after it.
  property int lastSpace: 0
  // The screen it is open on, where "+" puts the new workspace.
  property string monitorName: ""
  property string wallpaper: ""
  property var collect: []
  property string hovered: ""
  // What closing does once the windows are back: focus one, or go to a workspace.
  property var afterClose: null

  ShellIpc {
    target: "macos-mission-control"
    function toggle(): string { root.opened ? root.close(null) : root.open(); return "ok" }
  }

  function open() {
    if (root.opened || query.running) return
    root.collect = []
    root.hovered = ""
    query.running = true
  }

  function close(then) {
    if (!root.opened) return
    root.afterClose = then
    spreadAnim.stop()
    closeAnim.start()
  }

  function dispatch(lua) {
    Util.execDetached("hyprctl dispatch " + Util.shellQuote(lua))
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

  // Clients, monitors, workspaces and the wallpaper, a line of @@ apart.
  function load(text) {
    var parts = text.split("\n@@\n")
    var clients = [], monitors = [], workspaces = []
    try { clients = JSON.parse(parts[0]) } catch (e) {}
    try { monitors = JSON.parse(parts[1]) } catch (e) {}
    try { workspaces = JSON.parse(parts[2]) } catch (e) {}
    root.wallpaper = String(parts[3] || "").trim()

    var monitor = monitors.filter(function(m) { return m.focused })[0] || monitors[0]
    if (!monitor) return
    root.monitorName = monitor.name
    var active = monitor.activeWorkspace ? monitor.activeWorkspace.id : 0
    var seen = function(c) { return c.mapped && !c.hidden && c.workspace && c.workspace.id > 0 }
    var place = function(c) {
      return { address: c.address, title: String(c.title || c["class"] || ""), x: c.at[0] - monitor.x, y: c.at[1] - monitor.y,
               w: c.size[0], h: c.size[1], floating: c.floating, focus: c.focusHistoryID }
    }

    // Tiled windows first, floating ones on top, as on screen.
    root.windows = clients.filter(function(c) { return seen(c) && c.workspace.id === active })
      .map(place).sort(function(a, b) { return (a.floating ? 1 : 0) - (b.floating ? 1 : 0) })
    root.spaces = workspaces.filter(function(w) { return w.id > 0 && w.monitorID === monitor.id })
      .sort(function(a, b) { return a.id - b.id })
      .map(function(w) {
        return { id: w.id, name: String(w.name || w.id),
                 windows: clients.filter(function(c) { return seen(c) && c.workspace.id === w.id }).map(place) }
      })
    root.activeSpace = active
    root.lastSpace = workspaces.reduce(function(last, w) { return Math.max(last, w.id) }, 0)
    root.spreadOut = 0
    root.opened = true
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

  NumberAnimation {
    id: spreadAnim
    target: root; property: "spreadOut"; to: 1
    duration: Style.duration(320); easing.type: Easing.OutCubic
  }
  NumberAnimation {
    id: closeAnim
    target: root; property: "spreadOut"; to: 0
    duration: Style.duration(240); easing.type: Easing.OutCubic
    onFinished: {
      // What the click asked for runs first: it was made in the tile that was
      // clicked, which goes once Mission Control closes.
      var then = root.afterClose
      root.afterClose = null
      if (then) then()
      root.opened = false
    }
  }

  OverlayWindow {
    id: overlay
    shown: root.opened
    WlrLayershell.namespace: "omarchy-mission-control"
    onContentRevealedChanged: if (contentRevealed) { keys.forceActiveFocus(); spreadAnim.start() }

    // The strip of workspaces along the top, and the room the windows spread in.
    readonly property real stripHeight: Math.round(height * 0.11)
    readonly property real stripTop: Style.space(14)
    readonly property real pad: Style.space(48)
    readonly property var targets: MissionLayout.spread(root.windows, width - pad * 2,
      height - stripTop - stripHeight - Style.space(40) - pad * 2, Style.space(36))

    // The wallpaper, dimmed as the windows spread.
    Image {
      anchors.fill: parent
      source: root.wallpaper ? "file://" + root.wallpaper : ""
      sourceSize: Qt.size(overlay.width, overlay.height)
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      opacity: root.spreadOut
    }
    Rectangle { anchors.fill: parent; color: "black"; opacity: 0.28 * root.spreadOut }

    MouseArea {
      anchors.fill: parent
      onClicked: root.close(null)
    }

    Item {
      id: keys
      anchors.fill: parent
      focus: true
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape || (event.key === Qt.Key_Up && (event.modifiers & Qt.ControlModifier))) root.close(null)
        else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && root.hovered) {
          var address = root.hovered
          root.close(function() { root.dispatch("hl.dsp.focus({ window = \"address:" + address + "\" })") })
        } else return
        event.accepted = true
      }
    }

    // The workspaces, slid down from above.
    Row {
      id: strip
      anchors.horizontalCenter: parent.horizontalCenter
      y: overlay.stripTop - (1 - root.spreadOut) * (overlay.stripHeight + overlay.stripTop + Style.space(30))
      opacity: root.spreadOut
      spacing: Style.space(18)

      Repeater {
        // The workspaces, and a "+" for a new one, as on macOS.
        model: root.opened ? root.spaces.concat([{ id: 0, name: "", windows: [], add: true }]) : []

        delegate: SpaceMini {
          id: tile
          required property var modelData
          space: modelData
          wallpaper: root.wallpaper
          screenWidth: overlay.width
          screenHeight: overlay.height
          thumbHeight: overlay.stripHeight
          live: root.opened
          add: !!modelData.add
          ringed: !modelData.add && modelData.id === root.activeSpace
          hovered: spaceHover.hovered

          HoverHandler { id: spaceHover; cursorShape: Qt.PointingHandCursor }
          TapHandler {
            onTapped: {
              // "+" goes to a new, empty workspace: Hyprland keeps only a
              // workspace that is shown or has windows, so it can't wait
              // empty in the background. Left empty, it goes away again.
              var id = tile.modelData.add ? root.lastSpace + 1 : tile.modelData.id
              var isNew = !!tile.modelData.add, monitor = root.monitorName
              root.close(function() {
                var command = "hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })")
                // Omarchy gives a new number to a screen of its choosing;
                // the new workspace belongs on this one, once it exists.
                if (isNew) command += " && hyprctl dispatch " + Util.shellQuote("hl.dsp.workspace.move({ workspace = \"" + id + "\", monitor = \"" + monitor + "\" })")
                Util.execDetached(command)
              })
            }
          }
        }
      }
    }

    // The windows, each flying from its place on screen to its place in the spread.
    Repeater {
      model: root.opened ? root.windows : []

      delegate: Item {
        id: win
        required property var modelData
        required property int index
        readonly property var target: overlay.targets[index] || { x: modelData.x, y: modelData.y, w: modelData.w, h: modelData.h }
        readonly property real t: root.spreadOut
        readonly property bool hot: root.hovered === modelData.address
        x: modelData.x + (overlay.pad + target.x - modelData.x) * t
        y: modelData.y + (overlay.stripTop + overlay.stripHeight + Style.space(40) + overlay.pad + target.y - modelData.y) * t
        width: modelData.w + (target.w - modelData.w) * t
        height: modelData.h + (target.h - modelData.h) * t

        ClippingRectangle {
          anchors.fill: parent
          radius: Style.space(10)
          color: Qt.rgba(0.11, 0.11, 0.12, 0.85)
          ScreencopyView {
            anchors.fill: parent
            captureSource: root.opened ? root.toplevelFor(win.modelData.address) : null
            live: root.opened
            constraintSize: Qt.size(win.target.w * 2, win.target.h * 2)
          }
        }
        // The hovered window's ring.
        Rectangle {
          anchors.fill: parent
          anchors.margins: -Style.space(4)
          radius: Style.space(14)
          color: "transparent"
          border.width: 3
          border.color: "#0a84ff"
          visible: win.hot && root.spreadOut > 0.9
        }

        // Its title below it, in a dark capsule.
        Rectangle {
          visible: win.hot && root.spreadOut > 0.9
          anchors.horizontalCenter: parent.horizontalCenter
          y: parent.height + Style.space(10)
          width: Math.min(titleText.implicitWidth + Style.space(24), Math.max(parent.width, Style.space(160)))
          height: titleText.implicitHeight + Style.space(10)
          radius: height / 2
          color: Qt.rgba(0.11, 0.11, 0.12, 0.85)
          Text {
            id: titleText
            anchors.centerIn: parent
            width: parent.width - Style.space(24)
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: win.modelData.title
            color: "white"
            font.family: "Inter"
            font.pixelSize: Math.round(13 * Style.fontScale)
            font.weight: Font.Medium
          }
        }

        HoverHandler {
          onHoveredChanged: {
            if (hovered) root.hovered = win.modelData.address
            else if (root.hovered === win.modelData.address) root.hovered = ""
          }
        }
        TapHandler {
          onTapped: {
            var address = win.modelData.address
            root.close(function() { root.dispatch("hl.dsp.focus({ window = \"address:" + address + "\" })") })
          }
        }
      }
    }
  }
}
