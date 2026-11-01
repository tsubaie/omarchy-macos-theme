import QtQuick

// The window controls, drawn in the sidebar as macOS does: close, minimize and
// zoom, 12 px with 8 px between them. Pointing at any of them shows ×, − and +
// in all three, and they are gray while the window isn't the active one.
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
                { color: "#ff5f57", ink: "#4d0000", glyph: "×", action: "close", name: "Close" },
                { color: "#febc2e", ink: "#7a4500", glyph: "−", action: "minimize", name: "Minimize" },
                { color: "#28c840", ink: "#004d00", glyph: "+", action: "zoom", name: "Zoom" }
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

                Text {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: -0.5
                    visible: root.hovered
                    text: modelData.glyph
                    color: modelData.ink
                    font.pixelSize: 11
                    font.weight: Font.Bold
                }

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -3
                    onClicked: root[modelData.action]()
                }
            }
        }
    }

    // One hover area over all three, which takes no clicks, so pointing at
    // any light shows the symbols in all of them.
    MouseArea {
        id: hoverArea
        anchors.fill: lights
        anchors.margins: -4
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
    }
}
