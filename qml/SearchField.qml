import QtQuick

// The macOS search field: a magnifier, the "Search" placeholder, a clear
// button once there is text, and the accent focus ring while typing (HIG,
// Focus and selection: "use a focus ring for a text or search field").
// Esc clears it; ↑ and ↓ move through the results; Return opens one.
Rectangle {
    id: root

    property alias text: input.text
    signal move(int step)
    signal accepted()

    function focusField() {
        input.forceActiveFocus()
        input.selectAll()
    }

    function clear() {
        input.text = ""
        input.focus = false
    }

    implicitHeight: 28
    radius: 7
    color: Qt.rgba(1, 1, 1, input.activeFocus ? 0.1 : 0.07)
    border.width: input.activeFocus ? 2 : 1
    border.color: input.activeFocus ? Qt.rgba(0.04, 0.52, 1, 0.75) : Qt.rgba(1, 1, 1, 0.08)

    Accessible.role: Accessible.EditableText
    Accessible.name: "Search"

    Text {
        id: magnifier
        x: 8
        anchors.verticalCenter: parent.verticalCenter
        text: String.fromCodePoint(0xF0349)
        color: Qt.rgba(1, 1, 1, 0.55)
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 14
    }

    TextInput {
        id: input
        anchors.left: magnifier.right
        anchors.leftMargin: 6
        anchors.right: clearButton.visible ? clearButton.left : parent.right
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        clip: true
        color: "white"
        selectionColor: "#0a84ff"
        selectedTextColor: "white"
        font.pixelSize: 13

        Keys.onEscapePressed: root.clear()
        Keys.onUpPressed: root.move(-1)
        Keys.onDownPressed: root.move(1)
        Keys.onReturnPressed: root.accepted()
        Keys.onEnterPressed: root.accepted()

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: input.text === ""
            text: "Search"
            color: Qt.rgba(1, 1, 1, 0.55)
            font.pixelSize: 13
        }
    }

    // Clears the search; the circled ✕ macOS shows once there is text.
    Text {
        id: clearButton
        anchors.right: parent.right
        anchors.rightMargin: 7
        anchors.verticalCenter: parent.verticalCenter
        visible: input.text !== ""
        text: String.fromCodePoint(0xF0159)
        color: Qt.rgba(1, 1, 1, 0.55)
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 14

        Accessible.role: Accessible.Button
        Accessible.name: "Clear search"

        MouseArea {
            anchors.fill: parent
            anchors.margins: -4
            onClicked: { input.text = ""; input.forceActiveFocus() }
        }
    }

    // A click anywhere on the field starts typing.
    MouseArea {
        anchors.fill: parent
        anchors.rightMargin: clearButton.visible ? 28 : 0
        cursorShape: Qt.IBeamCursor
        onPressed: mouse => { input.forceActiveFocus(); mouse.accepted = false }
    }
}
