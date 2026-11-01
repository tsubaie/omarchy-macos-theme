import QtQuick

// The macOS slider: a thin track, blue up to a round white knob. It reports
// its value when let go, so the theme is changed once per drag.
Item {
    id: root

    property real from: 0
    property real to: 1
    property real value: 0
    property bool enabled: true
    property string accessibleName: ""
    signal moved(real value)

    Accessible.role: Accessible.Slider
    Accessible.name: accessibleName
    Accessible.description: shown.toFixed(2)

    // While dragging it shows where the knob is, and otherwise the value it
    // is given, so it follows the setting again once the theme has it.
    property real dragValue: value
    readonly property real shown: area.pressed ? dragValue : value
    readonly property real position: (shown - from) / (to - from)

    implicitWidth: 200
    implicitHeight: 22
    opacity: enabled ? 1 : 0.4

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        x: knob.width / 2
        width: parent.width - knob.width
        height: 4
        radius: 2
        color: "#4a4a4e"

        Rectangle {
            width: track.width * root.position
            height: parent.height
            radius: 2
            color: "#0a84ff"
        }
    }

    Rectangle {
        id: knob
        width: 20
        height: 20
        radius: 10
        anchors.verticalCenter: parent.verticalCenter
        x: track.width * root.position
        color: "white"
        border.width: 0.5
        border.color: Qt.rgba(0, 0, 0, 0.3)
    }

    MouseArea {
        id: area
        anchors.fill: parent
        enabled: root.enabled
        function valueAt(mouseX) {
            const p = Math.max(0, Math.min(1, (mouseX - knob.width / 2) / track.width))
            return root.from + p * (root.to - root.from)
        }
        onPressed: mouse => root.dragValue = valueAt(mouse.x)
        onPositionChanged: mouse => { if (pressed) root.dragValue = valueAt(mouse.x) }
        onReleased: root.moved(root.dragValue)
    }
}
