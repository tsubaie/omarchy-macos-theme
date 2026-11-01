import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Commons

// One workspace as a live miniature, labelled "Desktop N" below it: the
// wallpaper with each window drawn at its place. Mission Control's strip and
// the strip a dragged window drops onto both show these.
Item {
  id: mini

  // { name, windows: [{ address, x, y, w, h }] }, windows relative to the screen.
  property var space: ({ name: "", windows: [] })
  property string wallpaper: ""
  // The screen's size, which the miniature is a scaled copy of.
  property real screenWidth: 1
  property real screenHeight: 1
  property real thumbHeight: 100
  property bool live: false
  // Ringed in blue: the current workspace, or the one a drop would go to.
  property bool ringed: false
  property bool hovered: false
  // A "+" tile, for a new workspace, instead of a miniature.
  property bool add: false

  readonly property real scaleFactor: thumbHeight / Math.max(1, screenHeight)
  width: Math.round(screenWidth * scaleFactor)
  height: thumbHeight + Style.space(24)

  // The live window behind a Hyprland address, for the screen copy.
  function toplevelFor(address) {
    var want = String(address || "").replace(/^0x/, "")
    var values = Hyprland.toplevels.values
    for (var i = 0; i < values.length; i++) {
      if (String(values[i].address || "").replace(/^0x/, "") === want) return values[i].wayland
    }
    return null
  }

  ClippingRectangle {
    id: frame
    width: parent.width
    height: mini.thumbHeight
    radius: Style.space(8)
    color: mini.add ? Qt.rgba(1, 1, 1, mini.ringed ? 0.22 : 0.12) : "black"
    border.width: mini.ringed ? 2 : (mini.hovered ? 1 : 0)
    border.color: mini.ringed ? "#0a84ff" : Qt.rgba(1, 1, 1, 0.6)

    Image {
      visible: !mini.add
      anchors.fill: parent
      source: mini.wallpaper ? "file://" + mini.wallpaper : ""
      sourceSize: Qt.size(frame.width * 2, frame.height * 2)
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
    }
    Repeater {
      model: mini.add ? [] : mini.space.windows
      delegate: Item {
        required property var modelData
        x: Math.round(modelData.x * mini.scaleFactor)
        y: Math.round(modelData.y * mini.scaleFactor)
        width: Math.max(3, Math.round(modelData.w * mini.scaleFactor))
        height: Math.max(3, Math.round(modelData.h * mini.scaleFactor))
        Rectangle { anchors.fill: parent; radius: 2; color: Qt.rgba(0.11, 0.11, 0.12, 0.85) }
        ScreencopyView {
          anchors.fill: parent
          captureSource: mini.live ? mini.toplevelFor(parent.modelData.address) : null
          live: mini.live
          constraintSize: Qt.size(width * 2, height * 2)
        }
      }
    }
    Text {
      visible: mini.add
      anchors.centerIn: parent
      text: "+"
      color: "white"
      font.family: "Inter"
      font.pixelSize: Math.round(mini.thumbHeight * 0.4)
      font.weight: Font.Light
    }
  }

  Text {
    anchors.horizontalCenter: parent.horizontalCenter
    y: mini.thumbHeight + Style.space(6)
    textFormat: Text.PlainText
    text: mini.add ? "New Desktop" : "Desktop " + mini.space.name
    color: mini.ringed ? "#ffffff" : Qt.rgba(1, 1, 1, 0.7)
    font.family: "Inter"
    font.pixelSize: Math.round(12 * Style.fontScale)
  }
}
