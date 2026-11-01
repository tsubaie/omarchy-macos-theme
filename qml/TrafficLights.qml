import QtQuick

// The window controls, drawn in the sidebar as macOS does: close, minimize and
// zoom, 12 px with 8 px between them, showing ×, − and + while the pointer is
// over them, and gray while the window isn't the active one.
Row {
    id: root

    property bool active: true
    signal close()
    signal minimize()
    signal zoom()

    spacing: 8

    HoverHandler { id: hover }

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
            color: root.active || hover.hovered ? modelData.color : "#4e4e52"
            border.width: 0.5
            border.color: Qt.rgba(0, 0, 0, 0.25)

            Accessible.role: Accessible.Button
            Accessible.name: modelData.name
            Accessible.onPressAction: root[modelData.action]()

            Text {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -0.5
                visible: hover.hovered
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
