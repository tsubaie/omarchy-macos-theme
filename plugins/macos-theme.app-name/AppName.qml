import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// The focused app's name in bold, as macOS shows it beside the Apple menu so
// the active app is plain at a glance: the name its launcher gives it
// ("Files", not "org.gnome.Nautilus"), else its own app id.
BarWidget {
  id: root
  moduleName: "macos-theme.app-name"

  readonly property var toplevel: ToplevelManager.activeToplevel
  readonly property string appId: toplevel ? String(toplevel.appId || "") : ""
  readonly property var entry: appId ? DesktopEntries.heuristicLookup(appId) : null
  readonly property string name: entry && entry.name ? String(entry.name) : appId

  visible: name !== "" && !vertical
  // Measured apart from the label: the label's width comes from this one, and
  // an elided Text lays out again when its width changes, so taking its
  // implicitWidth here made a binding loop.
  TextMetrics { id: metrics; text: root.name; font: label.font }
  implicitWidth: visible ? Math.min(Style.space(240), Math.ceil(metrics.advanceWidth)) + Style.space(16) : 0
  implicitHeight: barSize

  Text {
    id: label
    anchors.verticalCenter: parent.verticalCenter
    anchors.left: parent.left
    anchors.leftMargin: Style.space(8)
    width: parent.width - Style.space(16)
    textFormat: Text.PlainText
    text: root.name
    elide: Text.ElideRight
    color: root.bar ? root.bar.barForeground : Commons.Color.foreground
    font.family: "Inter"
    font.weight: Font.Bold
    font.pixelSize: Style.font.body
  }
}
