// Uptime: how long since the computer started, read from /proc/uptime once a
// minute. An example widget for the macOS theme's desktop widgets; see
// docs/make-a-widget/SKILL.md. Copy this folder to
// ~/.config/omarchy/macos-theme-widgets/uptime/ to try it.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// The card around this is the theme's frosted glass; this fills it.
Item {
  id: root

  // The shell's scale: every size is a point size times this.
  readonly property real s: Style.fontScale
  property real seconds: 0

  FileView {
    id: uptime
    path: "/proc/uptime"
    onLoaded: root.seconds = parseFloat(text().split(" ")[0]) || 0
  }
  Timer {
    interval: 60000
    running: true
    repeat: true
    onTriggered: uptime.reload()
  }

  readonly property int days: Math.floor(seconds / 86400)
  readonly property int hours: Math.floor(seconds % 86400 / 3600)
  readonly property int minutes: Math.floor(seconds % 3600 / 60)

  Column {
    anchors.fill: parent
    anchors.margins: Math.round(14 * root.s)
    spacing: Math.round(2 * root.s)

    // A small colored title, as the theme's Calendar has its month.
    Text {
      text: "UPTIME"
      color: "#0a84ff"
      font.family: "Inter"
      font.weight: Font.DemiBold
      font.pixelSize: Math.round(11 * root.s)
    }
    Text {
      text: root.days > 0 ? root.days + "d " + root.hours + "h" : root.hours + "h " + root.minutes + "m"
      color: "white"
      font.family: "Inter Display"
      font.weight: Font.DemiBold
      font.pixelSize: Math.round(34 * root.s)
    }
    Text {
      text: "since the computer started"
      color: Qt.rgba(1, 1, 1, 0.6)
      font.family: "Inter"
      font.pixelSize: Math.round(11 * root.s)
      width: parent.width
      wrapMode: Text.WordWrap
    }
  }
}
