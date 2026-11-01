import QtQuick

// The macOS switch: a green capsule when on, gray when off, with a white knob
// that slides across.
Item {
    id: root

    property bool checked: false
    property bool enabled: true
    signal toggled(bool checked)

    implicitWidth: 38
    implicitHeight: 22
    opacity: enabled ? 1 : 0.4

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: root.checked ? "#30d158" : "#4a4a4e"
        Behavior on color { ColorAnimation { duration: 150 } }

        Rectangle {
            width: parent.height - 4
            height: width
            radius: width / 2
            y: 2
            x: root.checked ? parent.width - width - 2 : 2
            color: "white"
            Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.enabled
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled(!root.checked)
    }
}
