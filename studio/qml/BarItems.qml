import QtQuick
import "BarModel.js" as BarModel

// The menu bar's items in three groups, Left, Center and Right, plus those not
// in the menu bar: rows to show or hide with a switch, and to drag by their
// handle within a group or into another. Nothing changes until Apply: every
// change hands the new groups to `changed`.
Column {
    id: root

    // {left, center, right, hidden} as lists of ids (BarModel.groups).
    property var groups: ({ left: [], center: [], right: [], hidden: [] })
    // {id: name}
    property var names: ({})
    // The page this sits in, scrolled while a row is dragged near its edges,
    // and kept from scrolling under a drag.
    property Flickable flickable: null
    signal changed(var groups)

    readonly property var sections: [
        { id: "left", title: "Left" },
        { id: "center", title: "Center" },
        { id: "right", title: "Right" },
        { id: "hidden", title: "Not in the menu bar" }
    ]

    // While a row is dragged: its id, the row it moves with, and where it
    // would land ({ group, index }), or null over nothing.
    property string dragging: ""
    property Item draggedBody: null
    property var dropTarget: null
    property bool holding: false

    function name(id) {
        return names[id] || id
    }

    function moveTo(id, group, index) {
        changed(BarModel.move(groups, id, group, index))
    }

    // The keyboard's move: one place up or down, its handle keeping the focus
    // once the rows are rebuilt around it.
    property string refocus: ""
    function nudge(id, delta) {
        const next = BarModel.nudge(groups, id, delta)
        if (next === groups) return
        refocus = id
        changed(next)
    }

    // Every row and empty group, so a drag can tell what it is over from where
    // they are now; drop areas kept stale state once the rows were rebuilt.
    property var slots: []
    function addSlot(slot) { slots = slots.concat([slot]) }
    function removeSlot(item) { slots = slots.filter(s => s.item !== item) }

    // Over a row's upper half, before it; over its lower half, after it; over
    // an empty group, into it; elsewhere, nowhere.
    function aim() {
        if (!draggedBody) return
        const p = draggedBody.mapToItem(root, draggedBody.width / 2, draggedBody.height / 2)
        for (const s of slots) {
            if (s.id === dragging) continue
            const top = s.item.mapToItem(root, 0, 0)
            if (p.x < top.x || p.x > top.x + s.item.width || p.y < top.y || p.y >= top.y + s.item.height) continue
            dropTarget = { group: s.group, index: s.index + (s.empty || p.y < top.y + s.item.height / 2 ? 0 : 1) }
            return
        }
        // Over the dragged row's own place: it stays.
        const own = slots.find(s => s.id === dragging)
        if (own) {
            const top = own.item.mapToItem(root, 0, 0)
            if (p.y >= top.y && p.y < top.y + own.item.height) { dropTarget = { group: own.group, index: own.index }; return }
        }
        dropTarget = null
    }

    // Hold the page still from the moment a handle is pressed.
    Binding {
        when: root.flickable !== null && (root.holding || root.dragging !== "")
        target: root.flickable
        property: "interactive"
        value: false
    }

    // Near the top or bottom of the page, scroll it, keeping the dragged row
    // under the pointer.
    Timer {
        interval: 16
        repeat: true
        running: root.flickable !== null && root.draggedBody !== null
        onTriggered: {
            const f = root.flickable
            const y = root.draggedBody.mapToItem(f, 0, root.draggedBody.height / 2).y
            const edge = 48
            let step = 0
            if (y < edge) step = -Math.ceil((edge - y) / 4)
            else if (y > f.height - edge) step = Math.ceil((y - (f.height - edge)) / 4)
            const top = 0
            const bottom = Math.max(0, f.contentHeight - f.height)
            const next = Math.max(top, Math.min(bottom, f.contentY + step))
            root.draggedBody.y += next - f.contentY
            f.contentY = next
        }
    }

    spacing: 18
    width: parent ? parent.width : 0

    Repeater {
        model: root.sections

        delegate: Column {
            id: group
            required property var modelData
            readonly property var ids: root.groups[modelData.id] || []
            // The group a row is dragged out of draws above the others.
            z: root.dragging !== "" && ids.indexOf(root.dragging) >= 0 ? 10 : 0
            width: root.width
            spacing: 6
            objectName: "group-" + modelData.id

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

                Column {
                    id: rows
                    width: parent.width

                    // An empty group takes a drop as its first item.
                    Item {
                        visible: group.ids.length === 0
                        width: parent.width
                        height: visible ? 40 : 0

                        id: emptySlot
                        Component.onCompleted: root.addSlot({ item: emptySlot, group: group.modelData.id, index: 0, empty: true, id: "" })
                        Component.onDestruction: root.removeSlot(emptySlot)

                        Rectangle {
                            visible: !!root.dropTarget && root.dropTarget.group === group.modelData.id
                            x: 10
                            width: parent.width - 20
                            height: 2
                            radius: 1
                            anchors.verticalCenter: parent.verticalCenter
                            color: "#0a84ff"
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            leftPadding: 14
                            visible: !root.dropTarget || root.dropTarget.group !== group.modelData.id
                            text: group.modelData.id === "hidden" ? "Every item is in the menu bar" : "Drag items here"
                            color: Qt.rgba(1, 1, 1, 0.45)
                            font.pixelSize: 12
                        }
                    }

                    Repeater {
                        model: group.ids

                        delegate: Item {
                            id: row
                            required property string modelData
                            required property int index
                            width: rows.width
                            height: 40
                            z: handle.active ? 10 : 0
                            objectName: "row-" + modelData

                            Component.onCompleted: root.addSlot({ item: row, group: group.modelData.id, index: row.index, empty: false, id: row.modelData })
                            Component.onDestruction: root.removeSlot(row)

                            // Where the dragged item would go: a line at this
                            // row's top, or at its bottom for the last row.
                            Rectangle {
                                readonly property var t: root.dropTarget
                                visible: !!t && t.group === group.modelData.id
                                    && (t.index === row.index || (t.index === row.index + 1 && row.index === group.ids.length - 1))
                                x: 10
                                y: t && t.index === row.index + 1 ? row.height - 1 : -1
                                width: parent.width - 20
                                height: 2
                                radius: 1
                                color: "#0a84ff"
                                z: 5
                            }

                            Rectangle {
                                id: body
                                width: row.width
                                height: row.height
                                radius: 8
                                color: handle.active ? "#3a3a3e" : "transparent"
                                border.width: handle.active ? 1 : 0
                                border.color: Qt.rgba(1, 1, 1, 0.15)
                                onYChanged: if (handle.active) root.aim()

                                Text {
                                    x: 14
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 130
                                    elide: Text.ElideRight
                                    text: root.name(row.modelData)
                                    color: group.modelData.id === "hidden" ? Qt.rgba(1, 1, 1, 0.6) : "white"
                                    font.pixelSize: 13
                                }

                                MacSwitch {
                                    objectName: "switch-" + row.modelData
                                    anchors.right: grip.left
                                    anchors.rightMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    checked: group.modelData.id !== "hidden"
                                    enabled: root.enabled
                                    accessibleName: "Show " + root.name(row.modelData)
                                    // Off goes to "Not in the menu bar"; on to the end of the right side.
                                    onToggled: on => on ? root.moveTo(row.modelData, "right", (root.groups.right || []).length)
                                                        : root.moveTo(row.modelData, "hidden", (root.groups.hidden || []).length)
                                }

                                // The handle a row is dragged by.
                                Item {
                                    id: grip
                                    objectName: "grip-" + row.modelData
                                    anchors.right: parent.right
                                    anchors.rightMargin: 6
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 28
                                    height: 28

                                    Accessible.role: Accessible.Grip
                                    Accessible.name: "Move " + root.name(row.modelData)
                                    Accessible.description: "Up and Down move it, into the next group at either end"

                                    // Tab reaches it; Up and Down (with Alt too, as in
                                    // macOS lists) move the item a place at a time.
                                    activeFocusOnTab: true
                                    Keys.onUpPressed: root.nudge(row.modelData, -1)
                                    Keys.onDownPressed: root.nudge(row.modelData, 1)
                                    Component.onCompleted: if (root.refocus === row.modelData) { root.refocus = ""; forceActiveFocus() }

                                    FocusRing { controlRadius: 6 }

                                    Text {
                                        anchors.centerIn: parent
                                        text: "≡"
                                        color: Qt.rgba(1, 1, 1, root.enabled ? 0.5 : 0.2)
                                        font.pixelSize: 18
                                    }

                                    HoverHandler { cursorShape: Qt.OpenHandCursor }
                                    // Held down, not hovered: a PointHandler counted a hover too
                                    // and froze the page whenever the pointer passed a handle.
                                    // The drag that follows takes over from it; root.dragging
                                    // then keeps the page still.
                                    TapHandler {
                                        id: press
                                        enabled: root.enabled
                                        gesturePolicy: TapHandler.DragThreshold
                                        onPressedChanged: root.holding = pressed
                                        onCanceled: root.holding = false
                                    }

                                    DragHandler {
                                        id: handle
                                        target: body
                                        enabled: root.enabled
                                        xAxis.enabled: false
                                        grabPermissions: PointerHandler.CanTakeOverFromAnything
                                        onActiveChanged: {
                                            if (active) {
                                                root.dragging = row.modelData
                                                root.draggedBody = body
                                                root.dropTarget = null
                                                return
                                            }
                                            const target = root.dropTarget
                                            const id = root.dragging
                                            root.draggedBody = null
                                            root.dragging = ""
                                            root.dropTarget = null
                                            body.y = 0
                                            if (target) root.moveTo(id, target.group, target.index)
                                        }
                                    }
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
