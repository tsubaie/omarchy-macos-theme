import QtQuick

// The macOS segmented control, small size: a gray track with the chosen
// segment raised in a lighter gray, for picking one of a few places.
Item {
    id: root

    // [{ value, label }], left to right.
    property var options: []
    property string value: ""
    property bool enabled: true
    // What it picks, for screen readers; a row gives it its label.
    property string accessibleName: ""
    signal picked(string value)

    implicitWidth: options.length * 64
    implicitHeight: 22
    opacity: enabled ? 1 : 0.4

    Rectangle {
        anchors.fill: parent
        radius: 6
        color: "#3a3a3c"

        Row {
            anchors.fill: parent
            anchors.margins: 2

            Repeater {
                model: root.options

                delegate: Rectangle {
                    id: segment
                    required property var modelData
                    readonly property bool chosen: modelData.value === root.value
                    width: (parent.width) / root.options.length
                    height: parent.height
                    radius: 5
                    color: chosen ? "#636366" : "transparent"
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Accessible.role: Accessible.RadioButton
                    Accessible.name: root.accessibleName + ": " + modelData.label
                    Accessible.checkable: true
                    Accessible.checked: chosen
                    Accessible.onPressAction: if (root.enabled) root.picked(modelData.value)

                    Text {
                        anchors.centerIn: parent
                        text: segment.modelData.label
                        color: "white"
                        font.pixelSize: 12
                        font.weight: segment.chosen ? Font.Medium : Font.Normal
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: root.enabled
                        onClicked: root.picked(segment.modelData.value)
                    }
                }
            }
        }
    }
}
