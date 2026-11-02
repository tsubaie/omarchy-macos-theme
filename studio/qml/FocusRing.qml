import QtQuick

// The macOS keyboard focus ring: the accent blue, drawn just outside the
// control while it has focus. A click doesn't give focus, so the ring shows
// for the keyboard alone.
Rectangle {
    // The control's own corner radius; the ring follows it, a little wider.
    property real controlRadius: 6

    anchors.fill: parent
    anchors.margins: -3
    radius: controlRadius + 3
    color: "transparent"
    border.width: 3
    border.color: Qt.rgba(0.04, 0.52, 1, 0.65)
    visible: parent.activeFocus
}
