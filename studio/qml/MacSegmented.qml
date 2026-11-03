import QtQuick

// The macOS segmented control, small size: a gray track with the chosen
// segment raised in a lighter gray, for picking one of a few places.
Item {
    id: root

    // [{ value, label }], left to right.
    property var options: []
    property string value: ""
    // What it picks, for screen readers; a row gives it its label.
    property string accessibleName: ""
    property string reason: ""
    signal picked(string value)

    // Tab reaches it; Left and Right pick the segment beside the chosen one.
    activeFocusOnTab: true
    function step(by) {
        const at = options.findIndex(o => o.value === value)
        const next = options[Math.max(0, Math.min(options.length - 1, at + by))]
        if (next && next.value !== value) picked(next.value)
    }
    Keys.onLeftPressed: step(-1)
    Keys.onRightPressed: step(1)

    // Equal segments, each wide enough for the longest label, as macOS sizes them.
    implicitWidth: options.length * Math.max(64, widest.width + 24)
    implicitHeight: 22
    Text {
        id: widest
        visible: false
        font.pixelSize: 12
        font.weight: Font.Medium
        text: root.options.reduce((a, o) => o.label.length > a.length ? o.label : a, "")
    }
    opacity: enabled ? 1 : 0.4

    FocusRing { controlRadius: 6 }

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
                    Accessible.description: root.enabled ? "" : root.reason
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
