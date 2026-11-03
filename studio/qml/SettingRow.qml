import QtQuick

// One row in a group: a label and an optional note on the left, a control on
// the right, and a hairline under it unless it is the last row.
Item {
    id: root

    property string label: ""
    property string note: ""
    property bool last: false
    default property alias control: slot.data
    // Why the control can't be used now, from the control itself (its
    // reason), shown under the label while it can't.
    readonly property Item firstControl: slot.children.length > 0 ? slot.children[0] : null
    // The control that speaks for the row, when several sit side by side.
    property Item mainControl: firstControl
    readonly property string reason: mainControl && !mainControl.enabled && mainControl.reason ? mainControl.reason : ""
    // Changed and not applied yet, from the control itself: a blue dot by the label.
    readonly property bool changed: mainControl ? mainControl.changed === true : false

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
        // Room for the control, and for anything it shows to its left, such
        // as a slider's value.
        width: parent.width - slot.width - 42 - (slot.children.length > 0 && slot.children[0].leading ? slot.children[0].leading : 0)
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

        Text {
            width: parent.width
            visible: root.reason !== ""
            text: root.reason
            color: Qt.rgba(1, 1, 1, 0.6)
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
        visible: root.changed
        x: 5
        y: texts.y + 7
        width: 5
        height: 5
        radius: 2.5
        color: "#0a84ff"
        Accessible.role: Accessible.StaticText
        Accessible.name: root.label + ": changed, not applied yet"
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
