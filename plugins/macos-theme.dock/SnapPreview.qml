import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons

// The outline of where a dragged window will snap, for one screen: a frosted
// rounded sheet, as macOS and Windows show. look.lua reports the spot while
// the drag is over it; the sheet glides between spots and fades away when the
// drag leaves them. It takes no input.
PanelWindow {
  id: preview

  property bool shown: false
  property rect target

  // rect is in this screen's coordinates.
  function show(rect) {
    // Appearing, it grows in place rather than gliding in from the last spot.
    // Its position stays bound to target: assigning it would cut the binding.
    if (!preview.shown) {
      sheet.animate = false
      preview.target = rect
      preview.shown = true
      Qt.callLater(function() { sheet.animate = true })
      return
    }
    preview.target = rect
  }

  function hide() {
    preview.shown = false
  }

  anchors {
    top: true
    bottom: true
    left: true
    right: true
  }
  color: "transparent"
  visible: shown || sheet.opacity > 0
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.layer: WlrLayer.Top
  WlrLayershell.namespace: "omarchy-snap-preview"
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  mask: Region {}

  Rectangle {
    id: sheet

    property bool animate: true

    x: preview.target.x
    y: preview.target.y
    width: preview.target.width
    height: preview.target.height
    radius: 14
    color: Qt.rgba(1, 1, 1, 0.1)
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.35)
    opacity: preview.shown ? 1 : 0
    scale: preview.shown ? 1 : 0.94

    Behavior on x { enabled: sheet.animate; NumberAnimation { duration: Style.duration(180); easing.type: Easing.OutCubic } }
    Behavior on y { enabled: sheet.animate; NumberAnimation { duration: Style.duration(180); easing.type: Easing.OutCubic } }
    Behavior on width { enabled: sheet.animate; NumberAnimation { duration: Style.duration(180); easing.type: Easing.OutCubic } }
    Behavior on height { enabled: sheet.animate; NumberAnimation { duration: Style.duration(180); easing.type: Easing.OutCubic } }
    Behavior on opacity { NumberAnimation { duration: Style.duration(140); easing.type: Easing.OutCubic } }
    Behavior on scale { NumberAnimation { duration: Style.duration(180); easing.type: Easing.OutCubic } }
  }
}
