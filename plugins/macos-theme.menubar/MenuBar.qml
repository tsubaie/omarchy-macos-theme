import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons

// The macOS Tahoe menu bar look. macOS sets its whole interface in one sans
// serif, so the shell's text (bar, popups, notifications) uses Inter here;
// terminals keep their own font, which comes from their own configs. And as
// Tahoe does, a soft dark shade sits behind the see-through bar, over the
// wallpaper and under the windows, so its text and icons read on any
// wallpaper.
Item {
  id: root

  property var shell: null
  property var manifest: null

  Component.onCompleted: Style.fontFamily = "Inter"
  Component.onDestruction: Style.fontFamily = "monospace"

  Variants {
    model: Quickshell.screens

    delegate: Component {
      PanelWindow {
        required property var modelData

        screen: modelData
        anchors {
          top: true
          left: true
          right: true
        }
        implicitHeight: Style.space(72)
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.namespace: "omarchy-menubar-shade"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        mask: Region {}

        Rectangle {
          anchors.fill: parent
          gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.38) }
            GradientStop { position: 0.45; color: Qt.rgba(0, 0, 0, 0.16) }
            GradientStop { position: 1.0; color: "transparent" }
          }
        }
      }
    }
  }
}
