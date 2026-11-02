import QtQuick

// The macOS switch: the accent blue when on, gray when off, with a white knob
// that slides across. The small size, as macOS uses inside grouped rows so
// they keep one height (HIG, Toggles: "consider using a mini switch").
Item {
    id: root

    property bool checked: false
    property bool enabled: true
    // What it turns on or off, for screen readers; a row gives it its label.
    property string accessibleName: ""
    signal toggled(bool checked)

    implicitWidth: 32
    implicitHeight: 18
    opacity: enabled ? 1 : 0.4

    Accessible.role: Accessible.CheckBox
    Accessible.name: accessibleName
    Accessible.checkable: true
    Accessible.checked: checked
    Accessible.onToggleAction: if (enabled) toggled(!checked)
    Accessible.onPressAction: if (enabled) toggled(!checked)

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: root.checked ? "#0a84ff" : "#4a4a4e"
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
        onClicked: root.toggled(!root.checked)
    }
}
