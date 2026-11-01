import QtQuick
import "LayoutIcons.js" as LayoutIcons

// macOS theme: a workspace layout as a small map of its windows, for the bar
// and its layout menu, rather than a font's square, circle and triangle.
// Icons8 outline icons (workspaces/icons8.json):
//   dwindle    tiles: a tall one on the left, the rest split on the right
//   scrolling  a column in view, the ones beside it running off the edges
//   floating   two windows overlapping
Image {
  id: icon

  // "dwindle", "scrolling" or "floating"; anything else is tiling.
  property string mode: "dwindle"
  property color color: "white"
  property real size: 16

  width: size
  height: size
  source: LayoutIcons.icon(mode === "scrolling" || mode === "floating" ? mode : "dwindle", color.toString())
  // Drawn at three times its size and scaled down smoothly, so it stays
  // crisp at any display scale.
  sourceSize: Qt.size(size * 3, size * 3)
  smooth: true
  mipmap: true
}
