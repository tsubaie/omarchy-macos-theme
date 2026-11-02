import QtQuick

// A System Settings group: rows on a rounded panel, a hairline between them.
Rectangle {
    id: root

    default property alias rows: column.data
    property string title: ""

    width: parent ? parent.width : 0
    height: column.height + (title ? heading.height + 8 : 0)
    color: "transparent"

    Text {
        id: heading
        visible: root.title !== ""
        text: root.title
        color: Qt.rgba(1, 1, 1, 0.85)
        font.pixelSize: 13
        font.weight: Font.DemiBold
        leftPadding: 4
    }

    Rectangle {
        y: root.title ? heading.height + 8 : 0
        width: parent.width
        height: column.height
        radius: 10
        color: Qt.rgba(1, 1, 1, 0.06)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.08)

        Column {
            id: column
            width: parent.width
        }
    }
}
