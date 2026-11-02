import QtQuick
import QtQuick.Window

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

    Image {
        id: magnifier
        x: 6
        anchors.verticalCenter: parent.verticalCenter
        width: 17
        height: 17
        opacity: 0.6
        source: "qrc:/qt/qml/org/omarchy/macosstudio/assets/icons/search.svg"
        sourceSize: Qt.size(17 * Screen.devicePixelRatio * 2, 17 * Screen.devicePixelRatio * 2)
        smooth: true
        mipmap: true
    }

    TextInput {
        id: input
        anchors.left: magnifier.right
        anchors.leftMargin: 4
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
    Image {
        id: clearButton
        anchors.right: parent.right
        anchors.rightMargin: 7
        anchors.verticalCenter: parent.verticalCenter
        visible: input.text !== ""
        width: 18
        height: 18
        opacity: 0.6
        source: "qrc:/qt/qml/org/omarchy/macosstudio/assets/icons/clear.svg"
        sourceSize: Qt.size(18 * Screen.devicePixelRatio * 2, 18 * Screen.devicePixelRatio * 2)
        smooth: true
        mipmap: true

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
