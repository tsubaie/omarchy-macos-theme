import QtQuick

// The macOS slider: a thin track, blue up to a round white knob. It reports
// where the knob is as it is dragged (dragged), and its value when let go
// (moved), so the theme is changed once per drag and previews can follow.
Item {
    id: root

    property real from: 0
    property real to: 1
    property real value: 0
    property string accessibleName: ""
    property string reason: ""
    // How far an arrow key moves it; Page Up and Page Down move ten times that.
    property real step: (to - from) / 20
    signal moved(real value)
    signal dragged(real value)

    // Tab reaches it; the arrows, Page Up and Down, Home and End move it, as
    // on a macOS slider. Each press is a move, as a let-go drag is.
    activeFocusOnTab: true
    function nudge(by) {
        moved(Math.max(from, Math.min(to, value + by)))
    }
    Keys.onLeftPressed: nudge(-step)
    Keys.onDownPressed: nudge(-step)
    Keys.onRightPressed: nudge(step)
    Keys.onUpPressed: nudge(step)
    Keys.onPressed: event => {
        if (event.key === Qt.Key_PageUp) nudge(step * 10)
        else if (event.key === Qt.Key_PageDown) nudge(-step * 10)
        else if (event.key === Qt.Key_Home) moved(from)
        else if (event.key === Qt.Key_End) moved(to)
        else return
        event.accepted = true
    }

    Accessible.role: Accessible.Slider
    Accessible.name: accessibleName
    Accessible.description: enabled ? shown.toFixed(2) : reason

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

        FocusRing { controlRadius: knob.radius; visible: root.activeFocus }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        enabled: root.enabled
        function valueAt(mouseX) {
            const p = Math.max(0, Math.min(1, (mouseX - knob.width / 2) / track.width))
            return root.from + p * (root.to - root.from)
        }
        onPressed: mouse => { root.dragValue = valueAt(mouse.x); root.dragged(root.dragValue) }
        onPositionChanged: mouse => { if (pressed) { root.dragValue = valueAt(mouse.x); root.dragged(root.dragValue) } }
        onReleased: root.moved(root.dragValue)
    }
}
