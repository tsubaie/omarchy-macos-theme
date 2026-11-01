import QtQuick
import "Icons.js" as Icons

// macOS style icons on Omarchy's own Network, Bluetooth, Audio and Display
// widgets. They stay Omarchy's widgets, updates and all: this only hands each
// one's bar button an icon for the glyph it picked, and Omarchy's glyph comes
// back for any it shows that has no macOS icon, or when this is removed.
// It sits on the bar, unseen, as that is where the widgets are within reach.
Item {
    id: root

    // Set by the bar; unused, but a bar widget takes them.
    property var bar: null
    property string moduleName: ""
    property var settings: ({})

    readonly property var widgets: ["omarchy.network", "omarchy.bluetooth", "omarchy.audio", "omarchy.monitor"]
    property var patched: []

    visible: false
    implicitWidth: 0
    implicitHeight: 0

    // The bar surface this sits on.
    function surface() {
        var item = root
        while (item.parent) item = item.parent
        return item
    }

    // A widget's bar button: the item in it taking an iconComponent.
    function buttonIn(item) {
        if (item !== root && "iconComponent" in item && "text" in item) return item
        for (var i = 0; i < item.children.length; i++) {
            var found = buttonIn(item.children[i])
            if (found) return found
        }
        return null
    }

    function scan(item) {
        if ("moduleName" in item && root.widgets.indexOf(item.moduleName) >= 0 && item !== root) {
            var button = buttonIn(item)
            if (button && root.patched.indexOf(button) < 0) {
                button.iconComponent = Qt.binding(function() { return Icons.svg(button.text, "#fff") ? icon : null })
                root.patched.push(button)
            }
            return
        }
        for (var i = 0; i < item.children.length; i++) scan(item.children[i])
    }

    // Widgets are loaded again as they move about the bar; a look now and
    // then finds the new ones.
    Timer {
        interval: 1500
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: {
            root.patched = root.patched.filter(function(b) { try { return !!b.parent } catch (e) { return false } })
            root.scan(root.surface())
        }
    }

    Component.onDestruction: {
        for (var i = 0; i < patched.length; i++) {
            try { patched[i].iconComponent = null } catch (e) {}
        }
    }

    Component {
        id: icon

        Image {
            // The button this draws in, for its glyph and its colors.
            readonly property var button: {
                var item = parent
                while (item && !("iconComponent" in item)) item = item.parent
                return item
            }
            readonly property color tint: !button ? "white"
                : (button.active && button.useActiveColor ? button.activeColor : button.foreground)
            width: 18
            height: 18
            sourceSize: Qt.size(72, 72)
            smooth: true
            mipmap: true
            source: button ? Icons.source(button.text, tint.toString()) : ""
        }
    }
}
