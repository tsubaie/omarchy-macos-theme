import QtQuick

// The window controls, drawn in the sidebar as macOS does: close, minimize and
// zoom, 12 px with 8 px between them: plain colors, no symbols, and gray while
// the window isn't the active one (pointing at them brings the colors back).
Item {
    id: root

    property bool active: true
    readonly property bool hovered: hoverArea.containsMouse
    signal close()
    signal minimize()
    signal zoom()

    implicitWidth: lights.implicitWidth
    implicitHeight: lights.implicitHeight

    Row {
        id: lights
        spacing: 8

        Repeater {
            model: [
                { color: "#ff5f57", action: "close", name: "Close" },
                { color: "#febc2e", action: "minimize", name: "Minimize" },
                { color: "#28c840", action: "zoom", name: "Zoom" }
            ]

            delegate: Rectangle {
                required property var modelData
                width: 12
                height: 12
                radius: 6
                color: root.active || root.hovered ? modelData.color : "#4e4e52"
                border.width: 0.5
                border.color: Qt.rgba(0, 0, 0, 0.25)

                Accessible.role: Accessible.Button
                Accessible.name: modelData.name
                Accessible.onPressAction: root[modelData.action]()

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -3
                    onClicked: root[modelData.action]()
                }
            }
        }
    }

    // One hover area over all three, which takes no clicks: pointing at an
    // inactive window's lights colors them.
    MouseArea {
        id: hoverArea
        anchors.fill: lights
        anchors.margins: -4
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
    }
}
