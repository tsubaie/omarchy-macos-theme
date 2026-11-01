import QtQuick

// The menu bar's items, grouped by where they sit, as rows to show or hide
// with a switch and to drag by their handle within a group or into another.
// Hidden items wait in "Not in the menu bar" at the bottom; dragging one into
// a group, or switching it on, puts it back on the bar. Nothing changes until
// Apply: every change hands the whole arrangement to `changed`.
Column {
    id: root

    // {sections: {left: [ids], …}, hidden: [ids]}
    property var layout: ({ sections: {}, hidden: [] })
    // {id: name}
    property var names: ({})
    property bool enabled: true
    signal changed(var layout)

    readonly property var groups: [
        { id: "left", title: "Left" },
        { id: "centerBegin", title: "Center, start" },
        { id: "center", title: "Center" },
        { id: "centerEnd", title: "Center, end" },
        { id: "right", title: "Right" },
        { id: "tray", title: "Tray drawer" },
        { id: "hidden", title: "Not in the menu bar" }
    ]

    // Where a dragged row would land: { group, index }, or null.
    property var dropTarget: null
    property string dragging: ""

    function items(group) {
        return group === "hidden" ? (layout.hidden || []) : ((layout.sections || {})[group] || [])
    }

    // Moves an item to a group at an index, taking it out of where it was.
    function moveTo(id, group, index) {
        const next = { sections: {}, hidden: (layout.hidden || []).filter(x => x !== id) }
        for (const g in layout.sections || {}) next.sections[g] = layout.sections[g].filter(x => x !== id)
        const was = items(group).indexOf(id)
        if (was >= 0 && was < index) index -= 1
        const list = group === "hidden" ? next.hidden : (next.sections[group] = next.sections[group] || [])
        list.splice(Math.max(0, Math.min(index, list.length)), 0, id)
        changed(next)
    }

    spacing: 18
    width: parent ? parent.width : 0

    Repeater {
        model: root.groups

        delegate: Column {
            id: group
            required property var modelData
            readonly property var ids: root.items(modelData.id)
            width: root.width
            spacing: 6

            Text {
                text: group.modelData.title
                color: Qt.rgba(1, 1, 1, 0.85)
                font.pixelSize: 13
                font.weight: Font.DemiBold
                leftPadding: 4
            }

            Rectangle {
                width: parent.width
                height: rows.height
                radius: 10
                color: Qt.rgba(1, 1, 1, 0.06)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.08)

                // Dropping below the last row, or into an empty group, adds at the end.
                DropArea {
                    anchors.fill: parent
                    keys: ["bar-item"]
                    onEntered: root.dropTarget = { group: group.modelData.id, index: group.ids.length }
                }

                Column {
                    id: rows
                    width: parent.width

                    Text {
                        visible: group.ids.length === 0
                        width: parent.width
                        height: 40
                        verticalAlignment: Text.AlignVCenter
                        leftPadding: 14
                        text: group.modelData.id === "hidden" ? "Every item is in the menu bar" : "Drag items here"
                        color: Qt.rgba(1, 1, 1, 0.45)
                        font.pixelSize: 12
                    }

                    Repeater {
                        model: group.ids

                        delegate: Item {
                            id: row
                            required property string modelData
                            required property int index
                            readonly property bool targeted: !!root.dropTarget && root.dropTarget.group === group.modelData.id && root.dropTarget.index === index
                            width: rows.width
                            height: 40
                            z: body.Drag.active ? 10 : 0

                            // Hovering over a row puts the item before it.
                            DropArea {
                                anchors.fill: parent
                                keys: ["bar-item"]
                                onEntered: root.dropTarget = { group: group.modelData.id, index: row.index }
                            }

                            // Where the dragged item would go.
                            Rectangle {
                                visible: row.targeted && root.dragging !== row.modelData
                                width: parent.width - 20
                                x: 10
                                height: 2
                                radius: 1
                                color: "#0a84ff"
                            }

                            Rectangle {
                                id: body
                                width: row.width
                                height: row.height
                                radius: 8
                                color: Drag.active ? "#3a3a3e" : "transparent"
                                border.width: Drag.active ? 1 : 0
                                border.color: Qt.rgba(1, 1, 1, 0.15)

                                Drag.active: handle.active
                                Drag.keys: ["bar-item"]
                                Drag.hotSpot.x: width / 2
                                Drag.hotSpot.y: height / 2

                                Text {
                                    x: 14
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 120
                                    elide: Text.ElideRight
                                    text: root.names[row.modelData] || row.modelData
                                    color: group.modelData.id === "hidden" ? Qt.rgba(1, 1, 1, 0.6) : "white"
                                    font.pixelSize: 13
                                }

                                MacSwitch {
                                    anchors.right: grip.left
                                    anchors.rightMargin: 14
                                    anchors.verticalCenter: parent.verticalCenter
                                    checked: group.modelData.id !== "hidden"
                                    enabled: root.enabled
                                    accessibleName: "Show " + (root.names[row.modelData] || row.modelData)
                                    // Off goes to "Not in the menu bar"; on puts it at the end of the right side.
                                    onToggled: on => on ? root.moveTo(row.modelData, "right", root.items("right").length)
                                                        : root.moveTo(row.modelData, "hidden", root.items("hidden").length)
                                }

                                // The handle a row is dragged by.
                                Text {
                                    id: grip
                                    anchors.right: parent.right
                                    anchors.rightMargin: 14
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "≡"
                                    color: Qt.rgba(1, 1, 1, root.enabled ? 0.5 : 0.2)
                                    font.pixelSize: 18

                                    Accessible.role: Accessible.Grip
                                    Accessible.name: "Move " + (root.names[row.modelData] || row.modelData)

                                    DragHandler {
                                        id: handle
                                        target: body
                                        enabled: root.enabled
                                        xAxis.enabled: false
                                        onActiveChanged: {
                                            if (active) {
                                                root.dragging = row.modelData
                                                root.dropTarget = null
                                                return
                                            }
                                            const target = root.dropTarget
                                            const id = root.dragging
                                            root.dragging = ""
                                            root.dropTarget = null
                                            body.y = 0
                                            if (target) root.moveTo(id, target.group, target.index)
                                        }
                                    }

                                    HoverHandler { cursorShape: Qt.OpenHandCursor }
                                }
                            }

                            Rectangle {
                                visible: row.index < group.ids.length - 1
                                anchors.bottom: parent.bottom
                                x: 14
                                width: parent.width - 14
                                height: 1
                                color: Qt.rgba(1, 1, 1, 0.08)
                            }
                        }
                    }
                }
            }
        }
    }
}
