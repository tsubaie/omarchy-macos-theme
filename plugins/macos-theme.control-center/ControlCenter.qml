import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// macOS Control Center: one icon in the bar for the system's switches. The
// card shows what each is doing (network, Bluetooth, Tailscale), a volume
// slider, and tiles for the display and power; a click on a row opens
// Omarchy's own panel for it, which has the full controls.
BarWidget {
  id: root
  moduleName: "macos-theme.control-center"

  property bool open: false
  readonly property color foreground: root.bar ? root.bar.barForeground : Commons.Color.foreground

  // What each switch is doing, read when the card opens.
  property string networkKind: ""
  property string networkName: ""
  property bool bluetoothOn: false
  property bool tailscaleOn: false

  readonly property var sink: Pipewire.defaultAudioSink
  readonly property real volume: sink && sink.audio ? sink.audio.volume : 0
  readonly property bool muted: sink && sink.audio ? sink.audio.muted : false

  PwObjectTracker { objects: root.sink ? [root.sink] : [] }

  function close() {
    root.open = false
  }

  // Opens one of Omarchy's panels for the full controls. Their bar widgets
  // wait in the bar's tray drawer, which keeps the panels alive; a panel
  // opens on the focused screen, so this screen is focused first.
  function openPanel(target) {
    root.open = false
    var window = root.QsWindow.window
    var screen = window && window.screen ? String(window.screen.name || "") : ""
    var focus = screen ? "hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ monitor = \"" + screen + "\" })") + "; " : ""
    Util.execDetached(focus + "omarchy-shell -q " + target + " open")
  }

  onOpenChanged: if (open) status.running = true

  // One line each: network kind and name, Bluetooth power, Tailscale state.
  Process {
    id: status
    command: ["sh", "-c",
      "nmcli -t -f TYPE,STATE,CONNECTION dev 2>/dev/null | awk -F: '$2==\"connected\" && ($1==\"wifi\"||$1==\"ethernet\") {print $1\":\"$3; exit}'; "
      + "bluetoothctl show 2>/dev/null | grep -q 'Powered: yes' && echo on || echo off; "
      // Tailscale's own CLI may not reach its daemon from here; NetworkManager
      // sees its interface come up.
      + "nmcli -t -f DEVICE,STATE dev 2>/dev/null | grep -q '^tailscale0:connected' && echo on || echo off"]
    property var lines: []
    // Read as the lines come: the exit can be reported before the last one.
    stdout: SplitParser {
      onRead: function(line) {
        status.lines.push(String(line).trim())
        root.readStatus(status.lines)
      }
    }
    onStarted: lines = []
  }

  function readStatus(lines) {
    var network = lines[0] === "on" || lines[0] === "off" ? "" : String(lines[0] || "")
    var colon = network.indexOf(":")
    root.networkKind = colon > 0 ? network.slice(0, colon) : ""
    root.networkName = colon > 0 ? network.slice(colon + 1) : ""
    // Then Bluetooth and Tailscale; with no network, those come first.
    var rest = lines.filter(function(line) { return line === "on" || line === "off" })
    root.bluetoothOn = rest[0] === "on"
    root.tailscaleOn = rest[1] === "on"
  }

  visible: !vertical
  implicitWidth: Style.space(30)
  implicitHeight: barSize

  // The Control Center icon: two switches, one on and one off.
  Column {
    anchors.centerIn: parent
    spacing: Style.space(2)

    Repeater {
      model: [true, false]

      delegate: Rectangle {
        required property bool modelData
        width: Style.space(15)
        height: Style.space(6)
        radius: height / 2
        color: "transparent"
        border.width: 1
        border.color: root.foreground

        Rectangle {
          width: parent.height - 2
          height: width
          radius: width / 2
          anchors.verticalCenter: parent.verticalCenter
          x: parent.modelData ? parent.width - width - 1 : 1
          color: root.foreground
        }
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: root.open = !root.open
  }

  PopupCard {
    id: card
    anchorItem: root
    owner: root
    bar: root.bar
    open: root.open
    padding: Style.space(12)
    contentWidth: card.fittedContentWidth(Style.space(320))
    contentHeight: card.fittedContentHeight(content.implicitHeight)

    Column {
      id: content
      width: parent.width
      spacing: Style.space(10)

      // Network, Bluetooth and Tailscale.
      Tile {
        width: parent.width
        height: connectivity.implicitHeight + Style.space(16)

        Column {
          id: connectivity
          anchors.centerIn: parent
          width: parent.width - Style.space(16)
          spacing: Style.space(4)

          SwitchRow {
            glyph: root.networkKind === "wifi" ? "󰖩" : "󰈀"
            title: root.networkKind === "wifi" ? "Wi-Fi" : root.networkKind === "ethernet" ? "Ethernet" : "Network"
            subtitle: root.networkName || "Not Connected"
            on: root.networkKind !== ""
            onActivated: root.openPanel("omarchy.network")
          }
          SwitchRow {
            glyph: "󰂯"
            title: "Bluetooth"
            subtitle: root.bluetoothOn ? "On" : "Off"
            on: root.bluetoothOn
            onActivated: root.openPanel("omarchy.bluetooth")
          }
          SwitchRow {
            glyph: "󰖂"
            title: "Tailscale"
            subtitle: root.tailscaleOn ? "Connected" : "Off"
            on: root.tailscaleOn
            onActivated: root.openPanel("omarchy.tailscale")
          }
        }
      }

      // Sound: the output's volume, and its panel for the rest.
      Tile {
        width: parent.width
        height: sound.implicitHeight + Style.space(20)

        Column {
          id: sound
          anchors.centerIn: parent
          width: parent.width - Style.space(24)
          spacing: Style.space(8)

          Item {
            width: parent.width
            height: soundTitle.implicitHeight

            Text {
              id: soundTitle
              text: "Sound"
              color: Commons.Color.popups.text
              font.family: "Inter"
              font.weight: Font.DemiBold
              font.pixelSize: Style.font.body
            }

            Text {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: "󰒓"
              color: Commons.Color.popups.text
              opacity: soundMore.containsMouse ? 1 : 0.6
              font.pixelSize: Style.font.body

              MouseArea {
                id: soundMore
                anchors.fill: parent
                anchors.margins: -Style.space(4)
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openPanel("omarchy.audio")
              }
            }
          }

          Row {
            width: parent.width
            spacing: Style.space(10)

            Text {
              id: speaker
              anchors.verticalCenter: parent.verticalCenter
              text: root.muted ? "󰖁" : "󰕾"
              color: Commons.Color.popups.text
              font.pixelSize: Style.font.title

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: if (root.sink && root.sink.audio) root.sink.audio.muted = !root.muted
              }
            }

            // A macOS slider: a thick rounded track filled to the volume.
            Rectangle {
              id: track
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - speaker.width - parent.spacing
              height: Style.space(22)
              radius: height / 2
              color: Qt.rgba(1, 1, 1, 0.12)

              Rectangle {
                width: Math.max(track.height, track.width * Math.min(1, root.volume))
                height: parent.height
                radius: parent.radius
                color: root.muted ? Qt.rgba(1, 1, 1, 0.35) : "#f5f5f7"
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                function set(x) {
                  if (!root.sink || !root.sink.audio) return
                  root.sink.audio.muted = false
                  root.sink.audio.volume = Math.max(0, Math.min(1, x / track.width))
                }
                onPressed: function(mouse) { set(mouse.x) }
                onPositionChanged: function(mouse) { if (pressed) set(mouse.x) }
              }
            }
          }
        }
      }

      // Display and power, side by side.
      Row {
        width: parent.width
        spacing: Style.space(10)

        Repeater {
          model: [
            { glyph: "󰍹", title: "Display", target: "omarchy.monitor" },
            { glyph: "󰐥", title: "Power", target: "omarchy.power" }
          ]

          delegate: Tile {
            required property var modelData
            width: (parent.width - Style.space(10)) / 2
            height: Style.space(54)
            hoverable: true
            onActivated: root.openPanel(modelData.target)

            Row {
              anchors.verticalCenter: parent.verticalCenter
              x: Style.space(12)
              spacing: Style.space(10)

              Glyph { glyph: parent.parent.modelData.glyph; on: true }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: parent.parent.modelData.title
                color: Commons.Color.popups.text
                font.family: "Inter"
                font.weight: Font.DemiBold
                font.pixelSize: Style.font.body
              }
            }
          }
        }
      }
    }
  }

  // A rounded module of the card, as in macOS's Control Center.
  component Tile: Rectangle {
    id: tile
    property bool hoverable: false
    signal activated()

    radius: Style.space(14)
    color: Qt.rgba(1, 1, 1, tileMouse.containsMouse && tile.hoverable ? 0.14 : 0.08)

    MouseArea {
      id: tileMouse
      anchors.fill: parent
      enabled: tile.hoverable
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: tile.activated()
    }
  }

  // A round icon, blue while its switch is on.
  component Glyph: Rectangle {
    property string glyph
    property bool on: false

    width: Style.space(28)
    height: width
    radius: width / 2
    color: on ? "#0a84ff" : Qt.rgba(1, 1, 1, 0.14)

    Text {
      anchors.centerIn: parent
      text: parent.glyph
      color: "#ffffff"
      font.pixelSize: Style.font.body
    }
  }

  // A switch's icon, name and state; a click opens its panel.
  component SwitchRow: Rectangle {
    id: row
    property string glyph
    property string title
    property string subtitle
    property bool on: false
    signal activated()

    width: parent ? parent.width : 0
    height: Style.space(44)
    radius: Style.space(10)
    color: rowMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"

    Row {
      anchors.verticalCenter: parent.verticalCenter
      x: Style.space(6)
      spacing: Style.space(10)

      Glyph { anchors.verticalCenter: parent.verticalCenter; glyph: row.glyph; on: row.on }

      Column {
        anchors.verticalCenter: parent.verticalCenter

        Text {
          text: row.title
          color: Commons.Color.popups.text
          font.family: "Inter"
          font.weight: Font.DemiBold
          font.pixelSize: Style.font.body
        }

        Text {
          text: row.subtitle
          color: Commons.Color.popups.text
          opacity: 0.6
          font.family: "Inter"
          font.pixelSize: Style.font.caption
        }
      }
    }

    MouseArea {
      id: rowMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: row.activated()
    }
  }
}
