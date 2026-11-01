import QtQuick

// One row in a group: a label and an optional note on the left, a control on
// the right, and a hairline under it unless it is the last row.
Item {
    id: root

    property string label: ""
    property string note: ""
    property bool last: false
    default property alias control: slot.data

    width: parent ? parent.width : 0

    // The control on the right is named after the row, for screen readers.
    Component.onCompleted: {
        for (let i = 0; i < slot.data.length; i++) {
            const control = slot.data[i]
            if (control.accessibleName !== undefined && control.accessibleName === "") control.accessibleName = root.label
        }
    }
    height: Math.max(44, texts.height + 20)

    Column {
        id: texts
        anchors.verticalCenter: parent.verticalCenter
        x: 14
        width: parent.width - slot.width - 42
        spacing: 2

        Text {
            width: parent.width
            text: root.label
            color: "white"
            font.pixelSize: 13
            elide: Text.ElideRight
        }

        Text {
            width: parent.width
            visible: root.note !== ""
            text: root.note
            color: Qt.rgba(1, 1, 1, 0.5)
            font.pixelSize: 11
            wrapMode: Text.WordWrap
        }
    }

    Item {
        id: slot
        anchors.right: parent.right
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        width: childrenRect.width
        height: childrenRect.height
    }

    Rectangle {
        visible: !root.last
        anchors.bottom: parent.bottom
        x: 14
        width: parent.width - 14
        height: 1
        color: Qt.rgba(1, 1, 1, 0.08)
    }
}
